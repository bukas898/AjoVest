;; Token Vesting Scheduler 
;; Vesting system with enhanced security and tracking

;; Constants
(define-constant ERR-NOT-TREASURY-MANAGER (err u1))
(define-constant ERR-VESTING-NOT-ACTIVE (err u2))
(define-constant ERR-INVALID-SCHEDULE (err u3))
(define-constant ERR-ALREADY-CLAIMED (err u4))
(define-constant ERR-WRONG-IDENTITY-PROOF (err u5))
(define-constant ERR-VESTING-PERIOD-ACTIVE (err u6))
(define-constant ERR-INSUFFICIENT-ALLOCATION (err u7))
(define-constant ERR-INVALID-PARAMETER (err u8))
(define-constant ERR-SCHEDULE-EXISTS (err u9))
(define-constant MAX-SCHEDULE-ID u100)

;; Data Variables
(define-data-var treasury-manager principal tx-sender)
(define-data-var vesting-active bool false)
(define-data-var current-distribution uint u0)
(define-data-var kyc-verification-fee uint u1000000) ;; 1 STX
(define-data-var total-allocation uint u0)
(define-data-var current-epoch uint u0)

;; Schedule Structure
(define-map vesting-schedules
    uint
    {
        description: (string-utf8 256),
        identity-proof: (buff 32), ;; SHA256 hash for verification
        unlock-epoch: uint,
        token-amount: uint,
        claimed: bool
    }
)

;; Beneficiary Tracking
(define-map beneficiary-records
    principal
    {
        current-schedule: uint,
        claimed-schedules: (list 20 uint),
        last-claim: uint,
        total-claimed: uint
    }
)

;; Claim History
(define-map schedule-claims
    {schedule: uint, beneficiary: principal}
    {
        attempts: uint,
        claimed-at: (optional uint)
    }
)

;; Authorization
(define-private (is-manager)
    (is-eq tx-sender (var-get treasury-manager)))

;; Epoch Management
(define-public (update-epoch (new-epoch uint))
    (begin
        (asserts! (is-manager) ERR-NOT-TREASURY-MANAGER)
        (asserts! (>= new-epoch (var-get current-epoch)) ERR-INVALID-PARAMETER)
        (var-set current-epoch new-epoch)
        (ok true)))

;; Vesting Management Functions
(define-public (initialize-vesting)
    (begin
        (asserts! (is-manager) ERR-NOT-TREASURY-MANAGER)
        (var-set vesting-active true)
        (var-set current-distribution u0)
        (var-set total-allocation u0)
        (ok true)))

(define-public (create-schedule
    (schedule-id uint)
    (description (string-utf8 256))
    (identity-proof (buff 32))
    (unlock-epoch uint)
    (token-amount uint))
    (begin
        (asserts! (is-manager) ERR-NOT-TREASURY-MANAGER)
        
        ;; Validate schedule-id is within acceptable range
        (asserts! (<= schedule-id MAX-SCHEDULE-ID) ERR-INVALID-PARAMETER)
        
        ;; Check if schedule already exists to prevent overwriting
        (asserts! (is-none (map-get? vesting-schedules schedule-id)) ERR-SCHEDULE-EXISTS)
        
        ;; Validate unlock epoch is in the future
        (asserts! (>= unlock-epoch (var-get current-epoch)) ERR-INVALID-PARAMETER)
        
        ;; Validate identity proof is not empty
        (asserts! (> (len identity-proof) u0) ERR-INVALID-PARAMETER)
        
        ;; Validate description is not empty
        (asserts! (> (len description) u0) ERR-INVALID-PARAMETER)
        
        ;; Validate token amount is a positive amount
        (asserts! (> token-amount u0) ERR-INVALID-PARAMETER)
        
        ;; Set the schedule data
        (map-set vesting-schedules schedule-id
            {
                description: description,
                identity-proof: identity-proof,
                unlock-epoch: unlock-epoch,
                token-amount: token-amount,
                claimed: false
            })
            
        ;; Calculate new allocation safely
        (let ((new-allocation (+ (var-get total-allocation) token-amount)))
            ;; Make sure the addition doesn't overflow
            (asserts! (>= new-allocation (var-get total-allocation)) ERR-INVALID-PARAMETER)
            ;; Update the total allocation
            (var-set total-allocation new-allocation))
        (ok true)))

;; Beneficiary Registration
(define-public (complete-kyc)
    (begin
        (asserts! (var-get vesting-active) ERR-VESTING-NOT-ACTIVE)
        ;; Require KYC verification fee
        (try! (stx-transfer? (var-get kyc-verification-fee) tx-sender (var-get treasury-manager)))
        
        (map-set beneficiary-records tx-sender
            {
                current-schedule: u0,
                claimed-schedules: (list),
                last-claim: u0,
                total-claimed: u0
            })
        (ok true)))

;; Token Claim Functions
(define-public (claim-tokens
    (schedule-id uint)
    (verification (buff 32)))
    (let (
        (schedule (unwrap! (map-get? vesting-schedules schedule-id) ERR-INVALID-SCHEDULE))
        (beneficiary (unwrap! (map-get? beneficiary-records tx-sender) ERR-INVALID-SCHEDULE))
        (current-time (var-get current-epoch))
        )
        ;; Check schedule availability
        (asserts! (var-get vesting-active) ERR-VESTING-NOT-ACTIVE)
        (asserts! (>= current-time (get unlock-epoch schedule)) ERR-VESTING-PERIOD-ACTIVE)
        (asserts! (not (get claimed schedule)) ERR-ALREADY-CLAIMED)
        
        ;; Verify identity proof - directly compare the hashes
        (if (is-eq verification (get identity-proof schedule))
            (begin
                ;; Update schedule status
                (map-set vesting-schedules schedule-id
                    (merge schedule {claimed: true}))
                
                ;; Update beneficiary record
                (map-set beneficiary-records tx-sender
                    (merge beneficiary {
                        current-schedule: (+ schedule-id u1),
                        claimed-schedules: (unwrap! (as-max-len? 
                            (append (get claimed-schedules beneficiary) schedule-id) u20)
                            ERR-INVALID-SCHEDULE),
                        total-claimed: (+ (get total-claimed beneficiary) u1)
                    }))
                
                ;; Record claim
                (map-set schedule-claims
                    {schedule: schedule-id, beneficiary: tx-sender}
                    {
                        attempts: u1,
                        claimed-at: (some current-time)
                    })
                
                ;; Transfer tokens
                (try! (stx-transfer? (get token-amount schedule) (var-get treasury-manager) tx-sender))
                
                (ok true))
            ERR-WRONG-IDENTITY-PROOF)))

;; Read-only functions
(define-read-only (get-schedule-description (schedule-id uint))
    (match (map-get? vesting-schedules schedule-id)
        schedule (if (>= (var-get current-epoch) (get unlock-epoch schedule))
            (ok (get description schedule))
            ERR-VESTING-PERIOD-ACTIVE)
        ERR-INVALID-SCHEDULE))

(define-read-only (get-beneficiary-status (beneficiary principal))
    (map-get? beneficiary-records beneficiary))

(define-read-only (get-current-epoch)
    (var-get current-epoch))

(define-read-only (get-vesting-stats)
    {
        active: (var-get vesting-active),
        current-distribution: (var-get current-distribution),
        total-allocation: (var-get total-allocation),
        kyc-verification-fee: (var-get kyc-verification-fee),
        current-epoch: (var-get current-epoch)
    })