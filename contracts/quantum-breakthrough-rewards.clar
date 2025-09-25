;; title: quantum-breakthrough-rewards
;; version: 1.0.0
;; summary: Tokens for significant quantum computing research contributions and discoveries
;; description: This contract manages a token-based incentive system that recognizes and rewards
;;              significant quantum computing research contributions, breakthrough discoveries,
;;              and community achievements through a comprehensive reputation and rewards system.

;; traits
;;

;; token definitions
(define-fungible-token quantum-rewards)

;; constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u400))
(define-constant ERR_CONTRIBUTION_NOT_FOUND (err u401))
(define-constant ERR_INSUFFICIENT_TOKENS (err u402))
(define-constant ERR_INVALID_AMOUNT (err u403))
(define-constant ERR_ALREADY_CLAIMED (err u404))
(define-constant ERR_VOTING_CLOSED (err u405))
(define-constant ERR_ALREADY_VOTED (err u406))
(define-constant ERR_INVALID_CATEGORY (err u407))
(define-constant ERR_SELF_NOMINATION (err u408))
(define-constant TOKEN_NAME "Quantum Rewards Token")
(define-constant TOKEN_SYMBOL "QRT")
(define-constant TOKEN_DECIMALS u6)
(define-constant INITIAL_SUPPLY u1000000000000) ;; 1 million tokens with 6 decimals
(define-constant VOTING_PERIOD u1209600) ;; 2 weeks in seconds
(define-constant MIN_VALIDATORS_FOR_REWARD u3)
(define-constant MAX_REWARD_AMOUNT u100000000) ;; 100 tokens with decimals

;; Reward categories and their base amounts
(define-constant BREAKTHROUGH_DISCOVERY u50000000) ;; 50 tokens
(define-constant ALGORITHM_INNOVATION u30000000) ;; 30 tokens
(define-constant COLLABORATION_EXCELLENCE u20000000) ;; 20 tokens
(define-constant COMMUNITY_CONTRIBUTION u10000000) ;; 10 tokens
(define-constant RESEARCH_PUBLICATION u15000000) ;; 15 tokens
(define-constant PEER_REVIEW_PARTICIPATION u5000000) ;; 5 tokens

;; data vars
(define-data-var next-contribution-id uint u1)
(define-data-var next-voting-round-id uint u1)
(define-data-var total-rewards-distributed uint u0)
(define-data-var active-validators uint u0)
(define-data-var contract-paused bool false)

;; data maps
(define-map research-contributions 
    uint 
    {
        contributor: principal,
        title: (string-ascii 200),
        description: (string-ascii 1000),
        category: (string-ascii 50),
        evidence-url: (string-ascii 200),
        impact-score: uint, ;; 1-100 scale
        peer-reviews: uint,
        validation-votes: uint,
        rejection-votes: uint,
        reward-amount: uint,
        status: (string-ascii 20), ;; "pending", "approved", "rejected", "rewarded"
        submitted-at: uint,
        voting-deadline: uint,
        claimed: bool
    })

(define-map validator-profiles 
    principal 
    {
        reputation-score: uint,
        total-validations: uint,
        accurate-validations: uint,
        specialization: (string-ascii 50),
        stake-amount: uint,
        active: bool,
        registered-at: uint
    })

(define-map contribution-votes 
    {contribution-id: uint, validator: principal} 
    {
        vote: bool, ;; true for approval, false for rejection
        reasoning: (string-ascii 300),
        confidence-score: uint, ;; 1-5 scale
        voted-at: uint
    })

(define-map achievement-badges 
    {recipient: principal, badge-type: (string-ascii 50)} 
    {
        earned-at: uint,
        contribution-id: uint,
        level: uint, ;; Bronze=1, Silver=2, Gold=3, Platinum=4
        metadata: (string-ascii 200)
    })

(define-map user-balances 
    principal 
    {
        total-earned: uint,
        total-spent: uint,
        reputation-multiplier: uint, ;; 100 = 1.0x, 150 = 1.5x
        achievements-count: uint,
        last-reward-date: uint
    })

(define-map voting-rounds 
    uint 
    {
        contribution-ids: (list 20 uint),
        start-time: uint,
        end-time: uint,
        total-votes: uint,
        participating-validators: uint,
        round-status: (string-ascii 20) ;; "active", "completed", "cancelled"
    })

(define-map category-statistics 
    (string-ascii 50) 
    {
        total-contributions: uint,
        total-rewards: uint,
        average-impact: uint,
        top-contributor: (optional principal)
    })

(define-map milestone-rewards 
    principal 
    {
        contributions-milestone: uint, ;; next milestone (5, 10, 25, 50, 100)
        collaborations-milestone: uint,
        reviews-milestone: uint,
        lifetime-earnings: uint
    })

;; public functions

;; SIP-010 Standard Functions
(define-read-only (get-name)
    (ok TOKEN_NAME)
)

(define-read-only (get-symbol)
    (ok TOKEN_SYMBOL)
)

(define-read-only (get-decimals)
    (ok TOKEN_DECIMALS)
)

(define-read-only (get-balance (who principal))
    (ok (ft-get-balance quantum-rewards who))
)

(define-read-only (get-total-supply)
    (ok (ft-get-supply quantum-rewards))
)

(define-public (transfer (amount uint) (from principal) (to principal) (memo (optional (buff 34))))
    (begin
        (asserts! (is-eq from tx-sender) ERR_UNAUTHORIZED)
        (asserts! (not (var-get contract-paused)) (err u409))
        (ft-transfer? quantum-rewards amount from to)
    )
)

;; Initialize contract with initial supply
(define-private (initialize-contract)
    (begin
        (try! (ft-mint? quantum-rewards INITIAL_SUPPLY CONTRACT_OWNER))
        (ok true)
    )
)

;; Register as validator
(define-public (register-validator (specialization (string-ascii 50)) (stake-amount uint))
    (let
        (
            (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
        )
        (asserts! (not (var-get contract-paused)) (err u410))
        (asserts! (>= stake-amount u1000000) (err u411)) ;; minimum 1 token stake
        (asserts! (is-none (map-get? validator-profiles tx-sender)) (err u412))
        
        ;; Transfer stake to contract
        (try! (ft-transfer? quantum-rewards stake-amount tx-sender (as-contract tx-sender)))
        
        (map-set validator-profiles tx-sender {
            reputation-score: u100,
            total-validations: u0,
            accurate-validations: u0,
            specialization: specialization,
            stake-amount: stake-amount,
            active: true,
            registered-at: current-time
        })
        
        (var-set active-validators (+ (var-get active-validators) u1))
        
        (ok true)
    )
)

;; Submit research contribution
(define-public (submit-contribution (title (string-ascii 200)) (description (string-ascii 1000)) (category (string-ascii 50)) (evidence-url (string-ascii 200)) (impact-score uint))
    (let
        (
            (contribution-id (var-get next-contribution-id))
            (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
            (voting-deadline (+ current-time VOTING_PERIOD))
            (reward-amount (calculate-base-reward category impact-score))
        )
        (asserts! (not (var-get contract-paused)) (err u413))
        (asserts! (> (len title) u0) (err u414))
        (asserts! (> (len description) u0) (err u415))
        (asserts! (and (>= impact-score u1) (<= impact-score u100)) (err u416))
        (asserts! (is-valid-category category) ERR_INVALID_CATEGORY)
        
        (map-set research-contributions contribution-id {
            contributor: tx-sender,
            title: title,
            description: description,
            category: category,
            evidence-url: evidence-url,
            impact-score: impact-score,
            peer-reviews: u0,
            validation-votes: u0,
            rejection-votes: u0,
            reward-amount: reward-amount,
            status: "pending",
            submitted-at: current-time,
            voting-deadline: voting-deadline,
            claimed: false
        })
        
        ;; Update category statistics
        (let
            (
                (current-stats (default-to {total-contributions: u0, total-rewards: u0, average-impact: u0, top-contributor: none} 
                                          (map-get? category-statistics category)))
            )
            (map-set category-statistics category {
                total-contributions: (+ (get total-contributions current-stats) u1),
                total-rewards: (get total-rewards current-stats),
                average-impact: (/ (+ (* (get average-impact current-stats) (get total-contributions current-stats)) impact-score) (+ (get total-contributions current-stats) u1)),
                top-contributor: (get top-contributor current-stats)
            })
        )
        
        (var-set next-contribution-id (+ contribution-id u1))
        
        (ok contribution-id)
    )
)

;; Vote on contribution (validators only)
(define-public (vote-on-contribution (contribution-id uint) (approve bool) (reasoning (string-ascii 300)) (confidence uint))
    (let
        (
            (contribution (unwrap! (map-get? research-contributions contribution-id) ERR_CONTRIBUTION_NOT_FOUND))
            (validator (unwrap! (map-get? validator-profiles tx-sender) ERR_UNAUTHORIZED))
            (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
        )
        (asserts! (not (var-get contract-paused)) (err u417))
        (asserts! (get active validator) (err u418))
        (asserts! (< current-time (get voting-deadline contribution)) ERR_VOTING_CLOSED)
        (asserts! (is-eq (get status contribution) "pending") (err u419))
        (asserts! (is-none (map-get? contribution-votes {contribution-id: contribution-id, validator: tx-sender})) ERR_ALREADY_VOTED)
        (asserts! (and (>= confidence u1) (<= confidence u5)) (err u420))
        
        ;; Record vote
        (map-set contribution-votes {contribution-id: contribution-id, validator: tx-sender} {
            vote: approve,
            reasoning: reasoning,
            confidence-score: confidence,
            voted-at: current-time
        })
        
        ;; Update contribution vote counts
        (map-set research-contributions contribution-id 
            (merge contribution {
                validation-votes: (if approve (+ (get validation-votes contribution) u1) (get validation-votes contribution)),
                rejection-votes: (if approve (get rejection-votes contribution) (+ (get rejection-votes contribution) u1))
            }))
        
        ;; Update validator stats
        (map-set validator-profiles tx-sender 
            (merge validator {
                total-validations: (+ (get total-validations validator) u1)
            }))
        
        ;; Check if enough votes to finalize
        (let
            (
                (updated-contribution (unwrap-panic (map-get? research-contributions contribution-id)))
                (total-votes (+ (get validation-votes updated-contribution) (get rejection-votes updated-contribution)))
            )
            (if (>= total-votes MIN_VALIDATORS_FOR_REWARD)
                (finalize-contribution-voting contribution-id)
                (ok true)
            )
        )
    )
)

;; Claim approved reward
(define-public (claim-reward (contribution-id uint))
    (let
        (
            (contribution (unwrap! (map-get? research-contributions contribution-id) ERR_CONTRIBUTION_NOT_FOUND))
            (user-balance (default-to {total-earned: u0, total-spent: u0, reputation-multiplier: u100, achievements-count: u0, last-reward-date: u0} 
                                     (map-get? user-balances tx-sender)))
            (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
        )
        (asserts! (not (var-get contract-paused)) (err u421))
        (asserts! (is-eq (get contributor contribution) tx-sender) ERR_UNAUTHORIZED)
        (asserts! (is-eq (get status contribution) "approved") (err u422))
        (asserts! (not (get claimed contribution)) ERR_ALREADY_CLAIMED)
        
        ;; Apply reputation multiplier to reward
        (let
            (
                (base-reward (get reward-amount contribution))
                (multiplier (get reputation-multiplier user-balance))
                (final-reward (/ (* base-reward multiplier) u100))
            )
            ;; Mint and transfer rewards
            (try! (ft-mint? quantum-rewards final-reward tx-sender))
            
            ;; Update contribution status
            (map-set research-contributions contribution-id 
                (merge contribution {
                    status: "rewarded",
                    claimed: true
                }))
            
            ;; Update user balance
            (map-set user-balances tx-sender {
                total-earned: (+ (get total-earned user-balance) final-reward),
                total-spent: (get total-spent user-balance),
                reputation-multiplier: (get reputation-multiplier user-balance),
                achievements-count: (get achievements-count user-balance),
                last-reward-date: current-time
            })
            
            ;; Update global stats
            (var-set total-rewards-distributed (+ (var-get total-rewards-distributed) final-reward))
            
            ;; Check for milestone achievements
            (try! (check-milestone-achievements tx-sender))
            
            (ok final-reward)
        )
    )
)

;; Award badge for achievement
(define-public (award-badge (recipient principal) (badge-type (string-ascii 50)) (contribution-id uint) (level uint) (metadata (string-ascii 200)))
    (let
        (
            (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
        )
        (asserts! (or (is-eq tx-sender CONTRACT_OWNER) (is-some (map-get? validator-profiles tx-sender))) ERR_UNAUTHORIZED)
        (asserts! (and (>= level u1) (<= level u4)) (err u423))
        
        (map-set achievement-badges {recipient: recipient, badge-type: badge-type} {
            earned-at: current-time,
            contribution-id: contribution-id,
            level: level,
            metadata: metadata
        })
        
        ;; Update user achievements count
        (match (map-get? user-balances recipient)
            balance (map-set user-balances recipient 
                (merge balance {
                    achievements-count: (+ (get achievements-count balance) u1),
                    reputation-multiplier: (if (< (+ (get reputation-multiplier balance) u5) u200)
                                              (+ (get reputation-multiplier balance) u5)
                                              u200) ;; max 2x multiplier
                }))
            (map-set user-balances recipient {
                total-earned: u0,
                total-spent: u0,
                reputation-multiplier: u105,
                achievements-count: u1,
                last-reward-date: u0
            })
        )
        
        (ok true)
    )
)

;; read only functions

;; Get contribution details
(define-read-only (get-contribution (contribution-id uint))
    (map-get? research-contributions contribution-id)
)

;; Get validator profile
(define-read-only (get-validator (validator principal))
    (map-get? validator-profiles validator)
)

;; Get user balance info
(define-read-only (get-user-balance-info (user principal))
    (map-get? user-balances user)
)

;; Get vote details
(define-read-only (get-vote (contribution-id uint) (validator principal))
    (map-get? contribution-votes {contribution-id: contribution-id, validator: validator})
)

;; Get achievement badge
(define-read-only (get-badge (recipient principal) (badge-type (string-ascii 50)))
    (map-get? achievement-badges {recipient: recipient, badge-type: badge-type})
)

;; Get category statistics
(define-read-only (get-category-stats (category (string-ascii 50)))
    (map-get? category-statistics category)
)

;; Get contract statistics
(define-read-only (get-contract-stats)
    {
        total-rewards-distributed: (var-get total-rewards-distributed),
        active-validators: (var-get active-validators),
        total-contributions: (- (var-get next-contribution-id) u1),
        contract-paused: (var-get contract-paused)
    }
)

;; private functions

;; Calculate base reward amount based on category and impact
(define-private (calculate-base-reward (category (string-ascii 50)) (impact-score uint))
    (let
        (
            (base-amount (if (is-eq category "breakthrough")
                           BREAKTHROUGH_DISCOVERY
                           (if (is-eq category "algorithm")
                               ALGORITHM_INNOVATION
                               (if (is-eq category "collaboration")
                                   COLLABORATION_EXCELLENCE
                                   (if (is-eq category "community")
                                       COMMUNITY_CONTRIBUTION
                                       (if (is-eq category "publication")
                                           RESEARCH_PUBLICATION
                                           PEER_REVIEW_PARTICIPATION))))))
            (impact-multiplier (/ (+ u50 impact-score) u100)) ;; 0.5x to 1.5x based on impact
        )
        (if (< (/ (* base-amount impact-multiplier) u100) MAX_REWARD_AMOUNT)
            (/ (* base-amount impact-multiplier) u100)
            MAX_REWARD_AMOUNT)
    )
)

;; Check if category is valid
(define-private (is-valid-category (category (string-ascii 50)))
    (or (is-eq category "breakthrough")
        (or (is-eq category "algorithm")
            (or (is-eq category "collaboration")
                (or (is-eq category "community")
                    (or (is-eq category "publication")
                        (is-eq category "review")))))))

;; Finalize contribution voting
(define-private (finalize-contribution-voting (contribution-id uint))
    (let
        (
            (contribution (unwrap-panic (map-get? research-contributions contribution-id)))
            (approval-votes (get validation-votes contribution))
            (rejection-votes (get rejection-votes contribution))
        )
        (let
            (
                (new-status (if (> approval-votes rejection-votes) "approved" "rejected"))
            )
            (map-set research-contributions contribution-id 
                (merge contribution {
                    status: new-status
                }))
            
            ;; Update category stats if approved
            (if (is-eq new-status "approved")
                (let
                    (
                        (category (get category contribution))
                        (current-stats (default-to {total-contributions: u0, total-rewards: u0, average-impact: u0, top-contributor: none} 
                                                  (map-get? category-statistics category)))
                    )
                    (map-set category-statistics category 
                        (merge current-stats {
                            total-rewards: (+ (get total-rewards current-stats) (get reward-amount contribution))
                        }))
                )
                true
            )
            
            (ok true)
        )
    )
)

;; Check milestone achievements
(define-private (check-milestone-achievements (user principal))
    (let
        (
            (user-balance (default-to {total-earned: u0, total-spent: u0, reputation-multiplier: u100, achievements-count: u0, last-reward-date: u0} 
                                     (map-get? user-balances user)))
            (milestones (default-to {contributions-milestone: u5, collaborations-milestone: u5, reviews-milestone: u10, lifetime-earnings: u0} 
                                   (map-get? milestone-rewards user)))
        )
        ;; Check if user hit earnings milestones
        (if (and (>= (get total-earned user-balance) u100000000) (< (get lifetime-earnings milestones) u100000000))
            (try! (award-badge user "high-earner" u0 u2 "Earned 100+ tokens"))
            true
        )
        
        ;; Update milestone tracking
        (map-set milestone-rewards user {
            contributions-milestone: (get contributions-milestone milestones),
            collaborations-milestone: (get collaborations-milestone milestones),
            reviews-milestone: (get reviews-milestone milestones),
            lifetime-earnings: (get total-earned user-balance)
        })
        
        (ok true)
    )
)

;; Emergency pause (contract owner only)
(define-public (emergency-pause)
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (var-set contract-paused true)
        (ok true)
    )
)

;; Resume contract (contract owner only)
(define-public (resume-contract)
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (var-set contract-paused false)
        (ok true)
    )
)

;; Initialize the contract
(begin (initialize-contract))

