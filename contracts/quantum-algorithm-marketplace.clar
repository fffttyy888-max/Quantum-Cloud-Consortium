;; title: quantum-algorithm-marketplace
;; version: 1.0.0
;; summary: Trading platform for quantum algorithms and computational solutions
;; description: This contract facilitates the secure trading of quantum algorithms,
;;              enabling developers to monetize their innovations while ensuring
;;              intellectual property protection and performance verification.

;; traits
;;

;; token definitions
;;

;; constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u200))
(define-constant ERR_ALGORITHM_NOT_FOUND (err u201))
(define-constant ERR_INSUFFICIENT_PAYMENT (err u202))
(define-constant ERR_ALGORITHM_NOT_ACTIVE (err u203))
(define-constant ERR_ALREADY_PURCHASED (err u204))
(define-constant ERR_INVALID_PRICE (err u205))
(define-constant ERR_INVALID_LICENSE (err u206))
(define-constant ERR_SELF_PURCHASE (err u207))
(define-constant ERR_LICENSE_NOT_FOUND (err u208))
(define-constant MIN_PRICE u1000) ;; minimum price in micro-STX
(define-constant MAX_DESCRIPTION_LENGTH u500)
(define-constant PLATFORM_FEE_PERCENTAGE u5) ;; 5% platform fee

;; data vars
(define-data-var next-algorithm-id uint u1)
(define-data-var next-license-id uint u1)
(define-data-var total-algorithms uint u0)
(define-data-var total-transactions uint u0)
(define-data-var platform-revenue uint u0)

;; data maps
(define-map quantum-algorithms 
    uint 
    {
        developer: principal,
        name: (string-ascii 100),
        description: (string-ascii 500),
        category: (string-ascii 50),
        price: uint,
        license-type: (string-ascii 20), ;; "single", "unlimited", "enterprise"
        complexity-score: uint, ;; 1-100 scale
        performance-rating: uint, ;; 1-5 stars
        total-sales: uint,
        active: bool,
        created-at: uint,
        updated-at: uint
    })

(define-map algorithm-purchases 
    {algorithm-id: uint, buyer: principal} 
    {
        license-id: uint,
        purchase-price: uint,
        license-type: (string-ascii 20),
        purchased-at: uint,
        expires-at: (optional uint),
        usage-count: uint,
        active: bool
    })

(define-map algorithm-reviews 
    {algorithm-id: uint, reviewer: principal} 
    {
        rating: uint, ;; 1-5 stars
        review-text: (string-ascii 300),
        performance-score: uint, ;; 1-100
        created-at: uint
    })

(define-map developer-profiles 
    principal 
    {
        reputation-score: uint,
        total-algorithms: uint,
        total-sales: uint,
        total-revenue: uint,
        verified: bool,
        joined-at: uint
    })

(define-map algorithm-licenses 
    uint 
    {
        algorithm-id: uint,
        buyer: principal,
        license-type: (string-ascii 20),
        granted-at: uint,
        expires-at: (optional uint),
        usage-limit: (optional uint),
        usage-count: uint,
        royalty-percentage: uint,
        active: bool
    })

(define-map marketplace-stats 
    (string-ascii 20) 
    {
        total-value: uint,
        transaction-count: uint,
        average-price: uint
    })

;; public functions

;; List a quantum algorithm for sale
(define-public (list-algorithm (name (string-ascii 100)) (description (string-ascii 500)) (category (string-ascii 50)) (price uint) (license-type (string-ascii 20)) (complexity-score uint))
    (let
        (
            (algorithm-id (var-get next-algorithm-id))
            (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
        )
        (asserts! (> (len name) u0) (err u209))
        (asserts! (> (len description) u0) (err u210))
        (asserts! (>= price MIN_PRICE) ERR_INVALID_PRICE)
        (asserts! (and (>= complexity-score u1) (<= complexity-score u100)) (err u211))
        (asserts! (or (is-eq license-type "single") (or (is-eq license-type "unlimited") (is-eq license-type "enterprise"))) ERR_INVALID_LICENSE)
        
        ;; Create algorithm listing
        (map-set quantum-algorithms algorithm-id {
            developer: tx-sender,
            name: name,
            description: description,
            category: category,
            price: price,
            license-type: license-type,
            complexity-score: complexity-score,
            performance-rating: u0,
            total-sales: u0,
            active: true,
            created-at: current-time,
            updated-at: current-time
        })
        
        ;; Update developer profile
        (let
            (
                (current-profile (default-to 
                    {reputation-score: u100, total-algorithms: u0, total-sales: u0, total-revenue: u0, verified: false, joined-at: current-time} 
                    (map-get? developer-profiles tx-sender)))
            )
            (map-set developer-profiles tx-sender {
                reputation-score: (get reputation-score current-profile),
                total-algorithms: (+ (get total-algorithms current-profile) u1),
                total-sales: (get total-sales current-profile),
                total-revenue: (get total-revenue current-profile),
                verified: (get verified current-profile),
                joined-at: (get joined-at current-profile)
            })
        )
        
        (var-set next-algorithm-id (+ algorithm-id u1))
        (var-set total-algorithms (+ (var-get total-algorithms) u1))
        
        (ok algorithm-id)
    )
)

;; Purchase algorithm license
(define-public (purchase-algorithm (algorithm-id uint))
    (let
        (
            (algorithm (unwrap! (map-get? quantum-algorithms algorithm-id) ERR_ALGORITHM_NOT_FOUND))
            (license-id (var-get next-license-id))
            (purchase-price (get price algorithm))
            (platform-fee (/ (* purchase-price PLATFORM_FEE_PERCENTAGE) u100))
            (developer-payment (- purchase-price platform-fee))
            (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
        )
        (asserts! (get active algorithm) ERR_ALGORITHM_NOT_ACTIVE)
        (asserts! (not (is-eq (get developer algorithm) tx-sender)) ERR_SELF_PURCHASE)
        (asserts! (is-none (map-get? algorithm-purchases {algorithm-id: algorithm-id, buyer: tx-sender})) ERR_ALREADY_PURCHASED)
        
        ;; Transfer payment
        (try! (stx-transfer? purchase-price tx-sender (as-contract tx-sender)))
        
        ;; Pay developer (minus platform fee)
        (try! (as-contract (stx-transfer? developer-payment tx-sender (get developer algorithm))))
        
        ;; Create purchase record
        (map-set algorithm-purchases {algorithm-id: algorithm-id, buyer: tx-sender} {
            license-id: license-id,
            purchase-price: purchase-price,
            license-type: (get license-type algorithm),
            purchased-at: current-time,
            expires-at: (if (is-eq (get license-type algorithm) "single") (some (+ current-time u31536000)) none), ;; 1 year for single license
            usage-count: u0,
            active: true
        })
        
        ;; Create license record
        (map-set algorithm-licenses license-id {
            algorithm-id: algorithm-id,
            buyer: tx-sender,
            license-type: (get license-type algorithm),
            granted-at: current-time,
            expires-at: (if (is-eq (get license-type algorithm) "single") (some (+ current-time u31536000)) none),
            usage-limit: (if (is-eq (get license-type algorithm) "single") (some u100) none),
            usage-count: u0,
            royalty-percentage: u0,
            active: true
        })
        
        ;; Update algorithm stats
        (map-set quantum-algorithms algorithm-id 
            (merge algorithm {
                total-sales: (+ (get total-sales algorithm) u1),
                updated-at: current-time
            }))
        
        ;; Update developer profile
        (match (map-get? developer-profiles (get developer algorithm))
            profile (map-set developer-profiles (get developer algorithm) {
                reputation-score: (get reputation-score profile),
                total-algorithms: (get total-algorithms profile),
                total-sales: (+ (get total-sales profile) u1),
                total-revenue: (+ (get total-revenue profile) developer-payment),
                verified: (get verified profile),
                joined-at: (get joined-at profile)
            })
            false
        )
        
        ;; Update global stats
        (var-set next-license-id (+ license-id u1))
        (var-set total-transactions (+ (var-get total-transactions) u1))
        (var-set platform-revenue (+ (var-get platform-revenue) platform-fee))
        
        (ok license-id)
    )
)

;; Submit algorithm review
(define-public (submit-review (algorithm-id uint) (rating uint) (review-text (string-ascii 300)) (performance-score uint))
    (let
        (
            (algorithm (unwrap! (map-get? quantum-algorithms algorithm-id) ERR_ALGORITHM_NOT_FOUND))
            (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
        )
        (asserts! (and (>= rating u1) (<= rating u5)) (err u212))
        (asserts! (and (>= performance-score u1) (<= performance-score u100)) (err u213))
        (asserts! (is-some (map-get? algorithm-purchases {algorithm-id: algorithm-id, buyer: tx-sender})) (err u214))
        
        ;; Create review
        (map-set algorithm-reviews {algorithm-id: algorithm-id, reviewer: tx-sender} {
            rating: rating,
            review-text: review-text,
            performance-score: performance-score,
            created-at: current-time
        })
        
        ;; Update algorithm performance rating (simple average for now)
        (let
            (
                (current-rating (get performance-rating algorithm))
                (new-rating (if (is-eq current-rating u0) rating (/ (+ current-rating rating) u2)))
            )
            (map-set quantum-algorithms algorithm-id 
                (merge algorithm {
                    performance-rating: new-rating,
                    updated-at: current-time
                }))
        )
        
        (ok true)
    )
)

;; Update algorithm price (only by developer)
(define-public (update-algorithm-price (algorithm-id uint) (new-price uint))
    (let
        (
            (algorithm (unwrap! (map-get? quantum-algorithms algorithm-id) ERR_ALGORITHM_NOT_FOUND))
            (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
        )
        (asserts! (is-eq (get developer algorithm) tx-sender) ERR_UNAUTHORIZED)
        (asserts! (>= new-price MIN_PRICE) ERR_INVALID_PRICE)
        
        (map-set quantum-algorithms algorithm-id 
            (merge algorithm {
                price: new-price,
                updated-at: current-time
            }))
        
        (ok true)
    )
)

;; Toggle algorithm active status
(define-public (toggle-algorithm-status (algorithm-id uint))
    (let
        (
            (algorithm (unwrap! (map-get? quantum-algorithms algorithm-id) ERR_ALGORITHM_NOT_FOUND))
            (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
        )
        (asserts! (is-eq (get developer algorithm) tx-sender) ERR_UNAUTHORIZED)
        
        (map-set quantum-algorithms algorithm-id 
            (merge algorithm {
                active: (not (get active algorithm)),
                updated-at: current-time
            }))
        
        (ok true)
    )
)

;; Use algorithm (increment usage count)
(define-public (use-algorithm (algorithm-id uint))
    (let
        (
            (purchase (unwrap! (map-get? algorithm-purchases {algorithm-id: algorithm-id, buyer: tx-sender}) ERR_LICENSE_NOT_FOUND))
        )
        (asserts! (get active purchase) (err u215))
        
        ;; Check if license hasn't expired
        (match (get expires-at purchase)
            expiry (asserts! (< (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))) expiry) (err u216))
            true
        )
        
        ;; Update usage count
        (map-set algorithm-purchases {algorithm-id: algorithm-id, buyer: tx-sender} 
            (merge purchase {
                usage-count: (+ (get usage-count purchase) u1)
            }))
        
        ;; Update license usage count
        (match (map-get? algorithm-licenses (get license-id purchase))
            license (map-set algorithm-licenses (get license-id purchase) 
                (merge license {
                    usage-count: (+ (get usage-count license) u1)
                }))
            false
        )
        
        (ok true)
    )
)

;; read only functions

;; Get algorithm details
(define-read-only (get-algorithm (algorithm-id uint))
    (map-get? quantum-algorithms algorithm-id)
)

;; Get purchase details
(define-read-only (get-purchase (algorithm-id uint) (buyer principal))
    (map-get? algorithm-purchases {algorithm-id: algorithm-id, buyer: buyer})
)

;; Get algorithm review
(define-read-only (get-review (algorithm-id uint) (reviewer principal))
    (map-get? algorithm-reviews {algorithm-id: algorithm-id, reviewer: reviewer})
)

;; Get developer profile
(define-read-only (get-developer-profile (developer principal))
    (map-get? developer-profiles developer)
)

;; Get license details
(define-read-only (get-license (license-id uint))
    (map-get? algorithm-licenses license-id)
)

;; Check if user has purchased algorithm
(define-read-only (has-purchased (algorithm-id uint) (user principal))
    (is-some (map-get? algorithm-purchases {algorithm-id: algorithm-id, buyer: user}))
)

;; Get marketplace statistics
(define-read-only (get-marketplace-stats)
    {
        total-algorithms: (var-get total-algorithms),
        total-transactions: (var-get total-transactions),
        platform-revenue: (var-get platform-revenue),
        next-algorithm-id: (var-get next-algorithm-id)
    }
)

;; Calculate marketplace revenue for a category
(define-read-only (get-category-stats (category (string-ascii 20)))
    (map-get? marketplace-stats category)
)

;; private functions

;; Withdraw platform fees (only contract owner)
(define-public (withdraw-platform-fees (amount uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (<= amount (var-get platform-revenue)) (err u217))
        
        (try! (as-contract (stx-transfer? amount tx-sender CONTRACT_OWNER)))
        (var-set platform-revenue (- (var-get platform-revenue) amount))
        
        (ok true)
    )
)

