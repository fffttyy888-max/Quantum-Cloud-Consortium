;; title: research-collaboration-engine
;; version: 1.0.0
;; summary: Match researchers with complementary quantum computing expertise and resources
;; description: This contract facilitates research collaboration by connecting researchers
;;              with complementary skills, managing project collaborations, and
;;              enabling resource sharing agreements in the quantum computing space.

;; traits
;;

;; token definitions
;;

;; constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u300))
(define-constant ERR_RESEARCHER_NOT_FOUND (err u301))
(define-constant ERR_PROJECT_NOT_FOUND (err u302))
(define-constant ERR_INVALID_SKILLS (err u303))
(define-constant ERR_ALREADY_MEMBER (err u304))
(define-constant ERR_PROJECT_FULL (err u305))
(define-constant ERR_INVALID_COMMITMENT (err u306))
(define-constant ERR_COLLABORATION_NOT_FOUND (err u307))
(define-constant ERR_INVALID_STATUS (err u308))
(define-constant MAX_PROJECT_MEMBERS u10)
(define-constant MAX_SKILLS_PER_RESEARCHER u20)
(define-constant MIN_COMMITMENT_HOURS u10)
(define-constant MAX_COMMITMENT_HOURS u40)

;; data vars
(define-data-var next-researcher-id uint u1)
(define-data-var next-project-id uint u1)
(define-data-var next-collaboration-id uint u1)
(define-data-var total-researchers uint u0)
(define-data-var total-projects uint u0)
(define-data-var active-collaborations uint u0)

;; data maps
(define-map researcher-profiles 
    principal 
    {
        researcher-id: uint,
        name: (string-ascii 100),
        institution: (string-ascii 100),
        expertise-level: uint, ;; 1-5 scale (1=student, 2=graduate, 3=postdoc, 4=professor, 5=expert)
        specialization: (string-ascii 50),
        bio: (string-ascii 300),
        reputation-score: uint,
        total-collaborations: uint,
        successful-projects: uint,
        availability-hours: uint, ;; hours per week
        verified: bool,
        created-at: uint,
        updated-at: uint
    })

(define-map researcher-skills 
    {researcher: principal, skill-index: uint} 
    (string-ascii 50)
)

(define-map research-projects 
    uint 
    {
        creator: principal,
        title: (string-ascii 100),
        description: (string-ascii 500),
        field: (string-ascii 50),
        duration-weeks: uint,
        required-commitment: uint, ;; hours per week
        max-members: uint,
        current-members: uint,
        funding-amount: uint,
        status: (string-ascii 20), ;; "open", "active", "completed", "cancelled"
        required-skills: (list 10 (string-ascii 50)),
        created-at: uint,
        deadline: uint
    })

(define-map project-members 
    {project-id: uint, member: principal} 
    {
        role: (string-ascii 30),
        contribution-hours: uint,
        commitment-percentage: uint,
        joined-at: uint,
        status: (string-ascii 20), ;; "active", "inactive", "completed"
        performance-rating: uint
    })

(define-map collaboration-agreements 
    uint 
    {
        project-id: uint,
        participants: (list 10 principal),
        terms: (string-ascii 300),
        resource-allocation: (string-ascii 200),
        milestone-count: uint,
        completed-milestones: uint,
        total-funding: uint,
        start-date: uint,
        end-date: uint,
        status: (string-ascii 20)
    })

(define-map skill-demand 
    (string-ascii 50) 
    {
        total-projects: uint,
        avg-hourly-rate: uint,
        researchers-available: uint
    })

(define-map project-milestones 
    {project-id: uint, milestone-id: uint} 
    {
        title: (string-ascii 100),
        description: (string-ascii 300),
        deadline: uint,
        assigned-to: principal,
        completed: bool,
        completion-date: (optional uint)
    })

(define-map researcher-matches 
    {seeker: principal, candidate: principal} 
    {
        compatibility-score: uint, ;; 1-100
        skill-overlap: uint,
        availability-match: bool,
        location-compatible: bool,
        calculated-at: uint
    })

;; public functions

;; Register as a researcher
(define-public (register-researcher (name (string-ascii 100)) (institution (string-ascii 100)) (expertise-level uint) (specialization (string-ascii 50)) (bio (string-ascii 300)) (availability-hours uint))
    (let
        (
            (researcher-id (var-get next-researcher-id))
            (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
        )
        (asserts! (> (len name) u0) (err u309))
        (asserts! (> (len institution) u0) (err u310))
        (asserts! (and (>= expertise-level u1) (<= expertise-level u5)) (err u311))
        (asserts! (and (>= availability-hours u5) (<= availability-hours u50)) (err u312))
        (asserts! (is-none (map-get? researcher-profiles tx-sender)) (err u313))
        
        (map-set researcher-profiles tx-sender {
            researcher-id: researcher-id,
            name: name,
            institution: institution,
            expertise-level: expertise-level,
            specialization: specialization,
            bio: bio,
            reputation-score: u100,
            total-collaborations: u0,
            successful-projects: u0,
            availability-hours: availability-hours,
            verified: false,
            created-at: current-time,
            updated-at: current-time
        })
        
        (var-set next-researcher-id (+ researcher-id u1))
        (var-set total-researchers (+ (var-get total-researchers) u1))
        
        (ok researcher-id)
    )
)

;; Add skill to researcher profile
(define-public (add-researcher-skill (skill (string-ascii 50)) (skill-index uint))
    (let
        (
            (researcher (unwrap! (map-get? researcher-profiles tx-sender) ERR_RESEARCHER_NOT_FOUND))
        )
        (asserts! (< skill-index MAX_SKILLS_PER_RESEARCHER) ERR_INVALID_SKILLS)
        (asserts! (> (len skill) u0) ERR_INVALID_SKILLS)
        
        (map-set researcher-skills {researcher: tx-sender, skill-index: skill-index} skill)
        
        ;; Update skill demand statistics
        (let
            (
                (current-demand (default-to {total-projects: u0, avg-hourly-rate: u0, researchers-available: u0} 
                                           (map-get? skill-demand skill)))
            )
            (map-set skill-demand skill {
                total-projects: (get total-projects current-demand),
                avg-hourly-rate: (get avg-hourly-rate current-demand),
                researchers-available: (+ (get researchers-available current-demand) u1)
            })
        )
        
        (ok true)
    )
)

;; Create a new research project
(define-public (create-project (title (string-ascii 100)) (description (string-ascii 500)) (field (string-ascii 50)) (duration-weeks uint) (required-commitment uint) (max-members uint) (funding-amount uint) (required-skills (list 10 (string-ascii 50))) (deadline uint))
    (let
        (
            (project-id (var-get next-project-id))
            (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
            (researcher (unwrap! (map-get? researcher-profiles tx-sender) ERR_RESEARCHER_NOT_FOUND))
        )
        (asserts! (> (len title) u0) (err u314))
        (asserts! (> (len description) u0) (err u315))
        (asserts! (and (>= duration-weeks u1) (<= duration-weeks u104)) (err u316)) ;; max 2 years
        (asserts! (and (>= required-commitment MIN_COMMITMENT_HOURS) (<= required-commitment MAX_COMMITMENT_HOURS)) ERR_INVALID_COMMITMENT)
        (asserts! (and (>= max-members u2) (<= max-members MAX_PROJECT_MEMBERS)) (err u317))
        (asserts! (> deadline current-time) (err u318))
        
        (map-set research-projects project-id {
            creator: tx-sender,
            title: title,
            description: description,
            field: field,
            duration-weeks: duration-weeks,
            required-commitment: required-commitment,
            max-members: max-members,
            current-members: u1, ;; creator is first member
            funding-amount: funding-amount,
            status: "open",
            required-skills: required-skills,
            created-at: current-time,
            deadline: deadline
        })
        
        ;; Add creator as first member
        (map-set project-members {project-id: project-id, member: tx-sender} {
            role: "Lead Researcher",
            contribution-hours: u0,
            commitment-percentage: u100,
            joined-at: current-time,
            status: "active",
            performance-rating: u5
        })
        
        (var-set next-project-id (+ project-id u1))
        (var-set total-projects (+ (var-get total-projects) u1))
        
        (ok project-id)
    )
)

;; Join a research project
(define-public (join-project (project-id uint) (role (string-ascii 30)) (commitment-percentage uint))
    (let
        (
            (project (unwrap! (map-get? research-projects project-id) ERR_PROJECT_NOT_FOUND))
            (researcher (unwrap! (map-get? researcher-profiles tx-sender) ERR_RESEARCHER_NOT_FOUND))
            (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
        )
        (asserts! (is-eq (get status project) "open") (err u319))
        (asserts! (< (get current-members project) (get max-members project)) ERR_PROJECT_FULL)
        (asserts! (is-none (map-get? project-members {project-id: project-id, member: tx-sender})) ERR_ALREADY_MEMBER)
        (asserts! (and (>= commitment-percentage u10) (<= commitment-percentage u100)) ERR_INVALID_COMMITMENT)
        
        ;; Add member to project
        (map-set project-members {project-id: project-id, member: tx-sender} {
            role: role,
            contribution-hours: u0,
            commitment-percentage: commitment-percentage,
            joined-at: current-time,
            status: "active",
            performance-rating: u0
        })
        
        ;; Update project member count
        (map-set research-projects project-id 
            (merge project {
                current-members: (+ (get current-members project) u1)
            }))
        
        ;; Update researcher stats
        (map-set researcher-profiles tx-sender 
            (merge researcher {
                total-collaborations: (+ (get total-collaborations researcher) u1),
                updated-at: current-time
            }))
        
        (ok true)
    )
)

;; Create collaboration agreement
(define-public (create-collaboration (project-id uint) (participants (list 10 principal)) (terms (string-ascii 300)) (resource-allocation (string-ascii 200)) (milestone-count uint) (total-funding uint) (duration-weeks uint))
    (let
        (
            (collaboration-id (var-get next-collaboration-id))
            (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
            (project (unwrap! (map-get? research-projects project-id) ERR_PROJECT_NOT_FOUND))
        )
        (asserts! (is-eq (get creator project) tx-sender) ERR_UNAUTHORIZED)
        (asserts! (> milestone-count u0) (err u320))
        
        (map-set collaboration-agreements collaboration-id {
            project-id: project-id,
            participants: participants,
            terms: terms,
            resource-allocation: resource-allocation,
            milestone-count: milestone-count,
            completed-milestones: u0,
            total-funding: total-funding,
            start-date: current-time,
            end-date: (+ current-time (* duration-weeks u604800)), ;; weeks to seconds
            status: "active"
        })
        
        (var-set next-collaboration-id (+ collaboration-id u1))
        (var-set active-collaborations (+ (var-get active-collaborations) u1))
        
        (ok collaboration-id)
    )
)

;; Complete project milestone
(define-public (complete-milestone (project-id uint) (milestone-id uint))
    (let
        (
            (project (unwrap! (map-get? research-projects project-id) ERR_PROJECT_NOT_FOUND))
            (member (unwrap! (map-get? project-members {project-id: project-id, member: tx-sender}) (err u321)))
            (milestone (unwrap! (map-get? project-milestones {project-id: project-id, milestone-id: milestone-id}) (err u322)))
            (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
        )
        (asserts! (is-eq (get status member) "active") (err u323))
        (asserts! (not (get completed milestone)) (err u324))
        
        ;; Mark milestone as completed
        (map-set project-milestones {project-id: project-id, milestone-id: milestone-id} 
            (merge milestone {
                completed: true,
                completion-date: (some current-time)
            }))
        
        ;; Update member contribution
        (map-set project-members {project-id: project-id, member: tx-sender} 
            (merge member {
                contribution-hours: (+ (get contribution-hours member) u10) ;; assume 10 hours per milestone
            }))
        
        (ok true)
    )
)

;; Rate collaboration partner
(define-public (rate-collaborator (project-id uint) (collaborator principal) (rating uint))
    (let
        (
            (project (unwrap! (map-get? research-projects project-id) ERR_PROJECT_NOT_FOUND))
            (rater-member (unwrap! (map-get? project-members {project-id: project-id, member: tx-sender}) ERR_UNAUTHORIZED))
            (collaborator-member (unwrap! (map-get? project-members {project-id: project-id, member: collaborator}) (err u325)))
        )
        (asserts! (and (>= rating u1) (<= rating u5)) (err u326))
        (asserts! (not (is-eq tx-sender collaborator)) (err u327))
        
        ;; Update collaborator's performance rating
        (map-set project-members {project-id: project-id, member: collaborator} 
            (merge collaborator-member {
                performance-rating: rating
            }))
        
        ;; Update collaborator's reputation
        (match (map-get? researcher-profiles collaborator)
            researcher (let
                (
                    (current-score (get reputation-score researcher))
                    (new-score (/ (+ (* current-score u4) (* rating u20)) u5)) ;; weighted average
                )
                (map-set researcher-profiles collaborator 
                    (merge researcher {
                        reputation-score: new-score
                    }))
            )
            false
        )
        
        (ok true)
    )
)

;; read only functions

;; Get researcher profile
(define-read-only (get-researcher (researcher principal))
    (map-get? researcher-profiles researcher)
)

;; Get researcher skill by index
(define-read-only (get-researcher-skill (researcher principal) (skill-index uint))
    (map-get? researcher-skills {researcher: researcher, skill-index: skill-index})
)

;; Get project details
(define-read-only (get-project (project-id uint))
    (map-get? research-projects project-id)
)

;; Get project member details
(define-read-only (get-project-member (project-id uint) (member principal))
    (map-get? project-members {project-id: project-id, member: member})
)

;; Get collaboration agreement
(define-read-only (get-collaboration (collaboration-id uint))
    (map-get? collaboration-agreements collaboration-id)
)

;; Get skill demand statistics
(define-read-only (get-skill-demand (skill (string-ascii 50)))
    (map-get? skill-demand skill)
)

;; Get project milestone
(define-read-only (get-milestone (project-id uint) (milestone-id uint))
    (map-get? project-milestones {project-id: project-id, milestone-id: milestone-id})
)

;; Get researcher compatibility
(define-read-only (get-researcher-match (seeker principal) (candidate principal))
    (map-get? researcher-matches {seeker: seeker, candidate: candidate})
)

;; Check if researcher has specific skill
(define-read-only (has-skill (researcher principal) (skill (string-ascii 50)))
    (let
        (
            (skill-check (fold check-skill-helper (list u0 u1 u2 u3 u4 u5 u6 u7 u8 u9 u10 u11 u12 u13 u14 u15 u16 u17 u18 u19) {researcher: researcher, target-skill: skill, found: false}))
        )
        (get found skill-check)
    )
)

;; Get platform statistics
(define-read-only (get-platform-stats)
    {
        total-researchers: (var-get total-researchers),
        total-projects: (var-get total-projects),
        active-collaborations: (var-get active-collaborations),
        next-researcher-id: (var-get next-researcher-id)
    }
)

;; private functions

;; Helper function for skill checking
(define-private (check-skill-helper (skill-index uint) (acc {researcher: principal, target-skill: (string-ascii 50), found: bool}))
    (if (get found acc)
        acc
        (match (map-get? researcher-skills {researcher: (get researcher acc), skill-index: skill-index})
            skill (if (is-eq skill (get target-skill acc))
                     (merge acc {found: true})
                     acc)
            acc
        )
    )
)

;; Update project status (only project creator or contract owner)
(define-public (update-project-status (project-id uint) (new-status (string-ascii 20)))
    (let
        (
            (project (unwrap! (map-get? research-projects project-id) ERR_PROJECT_NOT_FOUND))
            (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
        )
        (asserts! (or (is-eq (get creator project) tx-sender) (is-eq tx-sender CONTRACT_OWNER)) ERR_UNAUTHORIZED)
        (asserts! (or (is-eq new-status "active") (or (is-eq new-status "completed") (or (is-eq new-status "cancelled") (is-eq new-status "open")))) ERR_INVALID_STATUS)
        
        (map-set research-projects project-id 
            (merge project {
                status: new-status
            }))
        
        ;; Update researcher success stats if project completed
        (if (is-eq new-status "completed")
            (begin
                ;; Update all project members' successful projects count
                (var-set active-collaborations (- (var-get active-collaborations) u1))
                true
            )
            true
        )
        
        (ok true)
    )
)

