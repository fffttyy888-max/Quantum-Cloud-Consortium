;; title: quantum-resource-scheduler
;; version: 1.0.0
;; summary: Fair allocation of quantum computing time across research institutions and companies
;; description: This contract manages the scheduling and allocation of quantum computing resources
;;              ensuring fair access, efficient utilization, and transparent billing.

;; traits
;;

;; token definitions
;;

;; constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_RESOURCE_NOT_FOUND (err u101))
(define-constant ERR_INVALID_TIME_SLOT (err u102))
(define-constant ERR_ALREADY_SCHEDULED (err u103))
(define-constant ERR_INSUFFICIENT_PAYMENT (err u104))
(define-constant ERR_INVALID_DURATION (err u105))
(define-constant ERR_RESOURCE_UNAVAILABLE (err u106))
(define-constant ERR_RESERVATION_NOT_FOUND (err u107))
(define-constant MIN_DURATION u60) ;; minimum 60 seconds
(define-constant MAX_DURATION u86400) ;; maximum 24 hours
(define-constant BASE_COST_PER_HOUR u1000) ;; base cost in micro-STX per hour

;; data vars
(define-data-var next-resource-id uint u1)
(define-data-var next-reservation-id uint u1)
(define-data-var total-resources uint u0)
(define-data-var total-reservations uint u0)
(define-data-var contract-balance uint u0)

;; data maps
(define-map quantum-resources 
    uint 
    {
        owner: principal,
        name: (string-ascii 50),
        qubits: uint,
        availability: bool,
        cost-per-hour: uint,
        location: (string-ascii 100),
        created-at: uint
    })

(define-map resource-schedules 
    {resource-id: uint, time-slot: uint} 
    {
        reserved-by: principal,
        reservation-id: uint,
        duration: uint,
        cost: uint,
        status: (string-ascii 20) ;; "active", "completed", "cancelled"
    })

(define-map user-reservations 
    uint 
    {
        user: principal,
        resource-id: uint,
        start-time: uint,
        duration: uint,
        total-cost: uint,
        status: (string-ascii 20),
        created-at: uint
    })

(define-map user-stats 
    principal 
    {
        total-reservations: uint,
        total-spent: uint,
        reputation-score: uint
    })

(define-map resource-utilization 
    uint 
    {
        total-hours-used: uint,
        total-revenue: uint,
        utilization-rate: uint
    })

;; public functions

;; Register a new quantum resource
(define-public (register-resource (name (string-ascii 50)) (qubits uint) (cost-per-hour uint) (location (string-ascii 100)))
    (let
        (
            (resource-id (var-get next-resource-id))
            (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
        )
        (asserts! (> (len name) u0) (err u108))
        (asserts! (> qubits u0) (err u109))
        (asserts! (> cost-per-hour u0) (err u110))
        
        (map-set quantum-resources resource-id {
            owner: tx-sender,
            name: name,
            qubits: qubits,
            availability: true,
            cost-per-hour: cost-per-hour,
            location: location,
            created-at: current-time
        })
        
        (map-set resource-utilization resource-id {
            total-hours-used: u0,
            total-revenue: u0,
            utilization-rate: u0
        })
        
        (var-set next-resource-id (+ resource-id u1))
        (var-set total-resources (+ (var-get total-resources) u1))
        
        (ok resource-id)
    )
)

;; Reserve quantum computing time
(define-public (reserve-time (resource-id uint) (start-time uint) (duration uint))
    (let
        (
            (resource (unwrap! (map-get? quantum-resources resource-id) ERR_RESOURCE_NOT_FOUND))
            (reservation-id (var-get next-reservation-id))
            (cost-per-hour (get cost-per-hour resource))
            (total-cost (/ (* duration cost-per-hour) u3600)) ;; convert seconds to hours for cost calculation
            (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
        )
        (asserts! (get availability resource) ERR_RESOURCE_UNAVAILABLE)
        (asserts! (>= duration MIN_DURATION) ERR_INVALID_DURATION)
        (asserts! (<= duration MAX_DURATION) ERR_INVALID_DURATION)
        (asserts! (>= start-time current-time) ERR_INVALID_TIME_SLOT)
        (asserts! (is-none (map-get? resource-schedules {resource-id: resource-id, time-slot: start-time})) ERR_ALREADY_SCHEDULED)
        
        ;; Transfer payment from user to contract
        (try! (stx-transfer? total-cost tx-sender (as-contract tx-sender)))
        
        ;; Create schedule entry
        (map-set resource-schedules 
            {resource-id: resource-id, time-slot: start-time} 
            {
                reserved-by: tx-sender,
                reservation-id: reservation-id,
                duration: duration,
                cost: total-cost,
                status: "active"
            })
        
        ;; Create reservation record
        (map-set user-reservations reservation-id {
            user: tx-sender,
            resource-id: resource-id,
            start-time: start-time,
            duration: duration,
            total-cost: total-cost,
            status: "active",
            created-at: current-time
        })
        
        ;; Update user stats
        (let
            (
                (current-stats (default-to {total-reservations: u0, total-spent: u0, reputation-score: u100} 
                                            (map-get? user-stats tx-sender)))
            )
            (map-set user-stats tx-sender {
                total-reservations: (+ (get total-reservations current-stats) u1),
                total-spent: (+ (get total-spent current-stats) total-cost),
                reputation-score: (get reputation-score current-stats)
            })
        )
        
        (var-set next-reservation-id (+ reservation-id u1))
        (var-set total-reservations (+ (var-get total-reservations) u1))
        (var-set contract-balance (+ (var-get contract-balance) total-cost))
        
        (ok reservation-id)
    )
)

;; Cancel a reservation (only by the user who made it)
(define-public (cancel-reservation (reservation-id uint))
    (let
        (
            (reservation (unwrap! (map-get? user-reservations reservation-id) ERR_RESERVATION_NOT_FOUND))
            (resource-id (get resource-id reservation))
            (start-time (get start-time reservation))
            (total-cost (get total-cost reservation))
        )
        (asserts! (is-eq (get user reservation) tx-sender) ERR_UNAUTHORIZED)
        (asserts! (is-eq (get status reservation) "active") (err u111))
        
        ;; Update reservation status
        (map-set user-reservations reservation-id 
            (merge reservation {status: "cancelled"}))
        
        ;; Update schedule status
        (match (map-get? resource-schedules {resource-id: resource-id, time-slot: start-time})
            schedule (map-set resource-schedules 
                {resource-id: resource-id, time-slot: start-time}
                (merge schedule {status: "cancelled"}))
            false
        )
        
        ;; Refund user (minus small cancellation fee of 5%)
        (let ((refund-amount (- total-cost (/ total-cost u20))))
            (try! (as-contract (stx-transfer? refund-amount tx-sender (get user reservation))))
            (var-set contract-balance (- (var-get contract-balance) refund-amount))
        )
        
        (ok true)
    )
)

;; Mark a reservation as completed (only by resource owner)
(define-public (complete-reservation (reservation-id uint))
    (let
        (
            (reservation (unwrap! (map-get? user-reservations reservation-id) ERR_RESERVATION_NOT_FOUND))
            (resource-id (get resource-id reservation))
            (resource (unwrap! (map-get? quantum-resources resource-id) ERR_RESOURCE_NOT_FOUND))
            (start-time (get start-time reservation))
            (duration (get duration reservation))
            (total-cost (get total-cost reservation))
        )
        (asserts! (is-eq (get owner resource) tx-sender) ERR_UNAUTHORIZED)
        (asserts! (is-eq (get status reservation) "active") (err u112))
        
        ;; Update reservation status
        (map-set user-reservations reservation-id 
            (merge reservation {status: "completed"}))
        
        ;; Update schedule status
        (match (map-get? resource-schedules {resource-id: resource-id, time-slot: start-time})
            schedule (map-set resource-schedules 
                {resource-id: resource-id, time-slot: start-time}
                (merge schedule {status: "completed"}))
            false
        )
        
        ;; Update resource utilization
        (let
            (
                (utilization (default-to {total-hours-used: u0, total-revenue: u0, utilization-rate: u0} 
                                         (map-get? resource-utilization resource-id)))
                (hours-used (/ duration u3600))
            )
            (map-set resource-utilization resource-id {
                total-hours-used: (+ (get total-hours-used utilization) hours-used),
                total-revenue: (+ (get total-revenue utilization) total-cost),
                utilization-rate: (+ (get utilization-rate utilization) u1)
            })
        )
        
        ;; Pay resource owner (contract takes 10% fee)
        (let ((owner-payment (- total-cost (/ total-cost u10))))
            (try! (as-contract (stx-transfer? owner-payment tx-sender (get owner resource))))
            (var-set contract-balance (- (var-get contract-balance) owner-payment))
        )
        
        (ok true)
    )
)

;; Update resource availability
(define-public (update-resource-availability (resource-id uint) (available bool))
    (let
        (
            (resource (unwrap! (map-get? quantum-resources resource-id) ERR_RESOURCE_NOT_FOUND))
        )
        (asserts! (is-eq (get owner resource) tx-sender) ERR_UNAUTHORIZED)
        
        (map-set quantum-resources resource-id 
            (merge resource {availability: available}))
        
        (ok true)
    )
)

;; read only functions

;; Get resource details
(define-read-only (get-resource (resource-id uint))
    (map-get? quantum-resources resource-id)
)

;; Get reservation details
(define-read-only (get-reservation (reservation-id uint))
    (map-get? user-reservations reservation-id)
)

;; Get user statistics
(define-read-only (get-user-stats (user principal))
    (map-get? user-stats user)
)

;; Get resource utilization
(define-read-only (get-resource-utilization (resource-id uint))
    (map-get? resource-utilization resource-id)
)

;; Check if time slot is available
(define-read-only (is-time-slot-available (resource-id uint) (start-time uint))
    (is-none (map-get? resource-schedules {resource-id: resource-id, time-slot: start-time}))
)

;; Get schedule for a specific time slot
(define-read-only (get-schedule (resource-id uint) (time-slot uint))
    (map-get? resource-schedules {resource-id: resource-id, time-slot: time-slot})
)

;; Get contract statistics
(define-read-only (get-contract-stats)
    {
        total-resources: (var-get total-resources),
        total-reservations: (var-get total-reservations),
        contract-balance: (var-get contract-balance)
    }
)

;; Calculate cost for a reservation
(define-read-only (calculate-cost (resource-id uint) (duration uint))
    (match (map-get? quantum-resources resource-id)
        resource (ok (/ (* duration (get cost-per-hour resource)) u3600))
        ERR_RESOURCE_NOT_FOUND
    )
)

;; private functions

;; Withdraw contract fees (only contract owner)
(define-public (withdraw-fees (amount uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (<= amount (var-get contract-balance)) (err u113))
        
        (try! (as-contract (stx-transfer? amount tx-sender CONTRACT_OWNER)))
        (var-set contract-balance (- (var-get contract-balance) amount))
        
        (ok true)
    )
)

