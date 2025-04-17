;; Token Vesting 

;; Constants
(define-constant ERR-NOT-TREASURY-MANAGER (err u1))
(define-constant ERR-VESTING-NOT-ACTIVE (err u2))
(define-constant ERR-INVALID-SCHEDULE (err u3))
(define-constant ERR-ALREADY-CLAIMED (err u4))
(define-constant ERR-VESTING-PERIOD-ACTIVE (err u6))
(define-constant ERR-INVALID-PARAMETER (err u8))

;; Data Variables
(define-data-var treasury-manager principal tx-sender)
(define-data-var vesting-active bool false)
(define-data-var current-distribution uint u0)
(define-data-var total-allocation uint u0)
(define-data-var current-epoch uint u0)

;; Schedule Structure
(define-map vesting-schedules
    uint
    {
        description: (string-utf8 256),
        unlock-epoch: uint,
        token-amount: uint,
        claimed: bool
    }
)

;; Beneficiary Tracking
(define-map beneficiary-records
    principal
    {
        total-claimed: uint
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
    (unlock-epoch uint)
    (token-amount uint))
    (begin
        (asserts! (is-manager) ERR-NOT-TREASURY-MANAGER)
        
        ;; Validate unlock epoch is in the future
        (asserts! (>= unlock-epoch (var-get current-epoch)) ERR-INVALID-PARAMETER)
        
        ;; Validate description is not empty
        (asserts! (> (len description) u0) ERR-INVALID-PARAMETER)
        
        ;; Validate token amount is a positive amount
        (asserts! (> token-amount u0) ERR-INVALID-PARAMETER)
        
        ;; Set the schedule data
        (map-set vesting-schedules schedule-id
            {
                description: description,
                unlock-epoch: unlock-epoch,
                token-amount: token-amount,
                claimed: false
            })
            
        ;; Calculate new allocation
        (var-set total-allocation (+ (var-get total-allocation) token-amount))
        (ok true)))

;; Token Claim Functions
(define-public (claim-tokens
    (schedule-id uint))
    (let (
        (schedule (unwrap! (map-get? vesting-schedules schedule-id) ERR-INVALID-SCHEDULE))
        (current-time (var-get current-epoch))
        )
        ;; Check schedule availability
        (asserts! (var-get vesting-active) ERR-VESTING-NOT-ACTIVE)
        (asserts! (>= current-time (get unlock-epoch schedule)) ERR-VESTING-PERIOD-ACTIVE)
        (asserts! (not (get claimed schedule)) ERR-ALREADY-CLAIMED)
        
        ;; Update schedule status
        (map-set vesting-schedules schedule-id
            (merge schedule {claimed: true}))
        
        ;; Update beneficiary record
        (match (map-get? beneficiary-records tx-sender)
            beneficiary (map-set beneficiary-records tx-sender
                {total-claimed: (+ (get total-claimed beneficiary) u1)})
            (map-set beneficiary-records tx-sender
                {total-claimed: u1}))
        
        ;; Transfer tokens
        (try! (stx-transfer? (get token-amount schedule) (var-get treasury-manager) tx-sender))
        
        (ok true)))

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
        current-epoch: (var-get current-epoch)
    })