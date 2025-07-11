;; Design Consultation Contract
;; Provides landscaping improvement recommendations

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-OWNER-ONLY (err u100))
(define-constant ERR-NOT-FOUND (err u101))
(define-constant ERR-INVALID-PARAMS (err u102))
(define-constant ERR-UNAUTHORIZED (err u103))
(define-constant ERR-INSUFFICIENT-BALANCE (err u104))

;; Data Variables
(define-data-var contract-active bool true)
(define-data-var total-consultations uint u0)
(define-data-var total-designers uint u0)
(define-data-var consultation-fee uint u200)

;; Data Maps
(define-map design-consultations
  { consultation-id: uint }
  {
    client: principal,
    designer: principal,
    property-address: (string-ascii 200),
    consultation-type: (string-ascii 50),
    budget-range: (string-ascii 50),
    preferences: (string-ascii 500),
    status: (string-ascii 20),
    created-date: uint,
    scheduled-date: uint,
    completion-date: uint
  }
)

(define-map landscape-designers
  { designer-id: uint }
  {
    designer: principal,
    name: (string-ascii 100),
    specialties: (string-ascii 300),
    experience-years: uint,
    rating: uint,
    total-consultations: uint,
    hourly-rate: uint,
    active: bool
  }
)

(define-map design-recommendations
  { consultation-id: uint, recommendation-id: uint }
  {
    category: (string-ascii 50),
    title: (string-ascii 100),
    description: (string-ascii 500),
    estimated-cost: uint,
    priority: uint,
    implementation-timeline: (string-ascii 100),
    materials-needed: (string-ascii 300)
  }
)

(define-map consultation-feedback
  { consultation-id: uint }
  {
    client-rating: uint,
    client-comments: (string-ascii 500),
    designer-notes: (string-ascii 500),
    follow-up-needed: bool,
    implementation-status: (string-ascii 50)
  }
)

(define-map user-balances
  { user: principal }
  { balance: uint }
)

(define-map designer-earnings
  { designer: principal }
  { earnings: uint }
)

;; Private Variables
(define-data-var next-consultation-id uint u1)

;; Public Functions

;; Register as a landscape designer
(define-public (register-designer (name (string-ascii 100)) (specialties (string-ascii 300)) (experience-years uint) (hourly-rate uint))
  (let
    (
      (designer-id (+ (var-get total-designers) u1))
    )
    (asserts! (var-get contract-active) (err u105))
    (asserts! (> (len name) u0) ERR-INVALID-PARAMS)
    (asserts! (> hourly-rate u0) ERR-INVALID-PARAMS)

    (map-set landscape-designers
      { designer-id: designer-id }
      {
        designer: tx-sender,
        name: name,
        specialties: specialties,
        experience-years: experience-years,
        rating: u50,
        total-consultations: u0,
        hourly-rate: hourly-rate,
        active: true
      }
    )

    (var-set total-designers designer-id)
    (ok designer-id)
  )
)

;; Request design consultation
(define-public (request-consultation (property-address (string-ascii 200)) (consultation-type (string-ascii 50)) (budget-range (string-ascii 50)) (preferences (string-ascii 500)))
  (let
    (
      (consultation-id (var-get next-consultation-id))
      (user-balance (default-to u0 (get balance (map-get? user-balances { user: tx-sender }))))
      (fee (var-get consultation-fee))
    )
    (asserts! (var-get contract-active) (err u105))
    (asserts! (> (len property-address) u0) ERR-INVALID-PARAMS)
    (asserts! (>= user-balance fee) ERR-INSUFFICIENT-BALANCE)

    ;; Deduct consultation fee
    (map-set user-balances
      { user: tx-sender }
      { balance: (- user-balance fee) }
    )

    (map-set design-consultations
      { consultation-id: consultation-id }
      {
        client: tx-sender,
        designer: CONTRACT-OWNER, ;; Will be assigned later
        property-address: property-address,
        consultation-type: consultation-type,
        budget-range: budget-range,
        preferences: preferences,
        status: "requested",
        created-date: block-height,
        scheduled-date: u0,
        completion-date: u0
      }
    )

    (var-set next-consultation-id (+ consultation-id u1))
    (var-set total-consultations (+ (var-get total-consultations) u1))
    (ok consultation-id)
  )
)

;; Assign designer to consultation
(define-public (assign-designer (consultation-id uint) (designer-id uint))
  (let
    (
      (consultation-data (unwrap! (map-get? design-consultations { consultation-id: consultation-id }) ERR-NOT-FOUND))
      (designer-data (unwrap! (map-get? landscape-designers { designer-id: designer-id }) ERR-NOT-FOUND))
    )
    (asserts! (var-get contract-active) (err u105))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (get active designer-data) (err u106))
    (asserts! (is-eq (get status consultation-data) "requested") (err u107))

    (map-set design-consultations
      { consultation-id: consultation-id }
      (merge consultation-data {
        designer: (get designer designer-data),
        status: "assigned"
      })
    )
    (ok true)
  )
)

;; Schedule consultation
(define-public (schedule-consultation (consultation-id uint) (scheduled-date uint))
  (let
    (
      (consultation-data (unwrap! (map-get? design-consultations { consultation-id: consultation-id }) ERR-NOT-FOUND))
    )
    (asserts! (var-get contract-active) (err u105))
    (asserts! (is-eq (get designer consultation-data) tx-sender) ERR-UNAUTHORIZED)
    (asserts! (is-eq (get status consultation-data) "assigned") (err u108))
    (asserts! (> scheduled-date block-height) ERR-INVALID-PARAMS)

    (map-set design-consultations
      { consultation-id: consultation-id }
      (merge consultation-data {
        scheduled-date: scheduled-date,
        status: "scheduled"
      })
    )
    (ok true)
  )
)

;; Add design recommendation
(define-public (add-recommendation (consultation-id uint) (recommendation-id uint) (category (string-ascii 50)) (title (string-ascii 100)) (description (string-ascii 500)) (estimated-cost uint) (priority uint))
  (let
    (
      (consultation-data (unwrap! (map-get? design-consultations { consultation-id: consultation-id }) ERR-NOT-FOUND))
    )
    (asserts! (var-get contract-active) (err u105))
    (asserts! (is-eq (get designer consultation-data) tx-sender) ERR-UNAUTHORIZED)
    (asserts! (> (len title) u0) ERR-INVALID-PARAMS)
    (asserts! (and (>= priority u1) (<= priority u5)) ERR-INVALID-PARAMS)

    (map-set design-recommendations
      { consultation-id: consultation-id, recommendation-id: recommendation-id }
      {
        category: category,
        title: title,
        description: description,
        estimated-cost: estimated-cost,
        priority: priority,
        implementation-timeline: "4-6 weeks",
        materials-needed: ""
      }
    )
    (ok true)
  )
)

;; Complete consultation
(define-public (complete-consultation (consultation-id uint))
  (let
    (
      (consultation-data (unwrap! (map-get? design-consultations { consultation-id: consultation-id }) ERR-NOT-FOUND))
      (designer-data (unwrap! (map-get? landscape-designers { designer-id: u1 }) (err u109))) ;; Simplified lookup
    )
    (asserts! (var-get contract-active) (err u105))
    (asserts! (is-eq (get designer consultation-data) tx-sender) ERR-UNAUTHORIZED)
    (asserts! (is-eq (get status consultation-data) "scheduled") (err u110))

    (map-set design-consultations
      { consultation-id: consultation-id }
      (merge consultation-data {
        status: "completed",
        completion-date: block-height
      })
    )

    ;; Update designer stats
    (map-set landscape-designers
      { designer-id: u1 }
      (merge designer-data {
        total-consultations: (+ (get total-consultations designer-data) u1)
      })
    )

    (ok true)
  )
)

;; Submit consultation feedback
(define-public (submit-feedback (consultation-id uint) (client-rating uint) (client-comments (string-ascii 500)) (follow-up-needed bool))
  (let
    (
      (consultation-data (unwrap! (map-get? design-consultations { consultation-id: consultation-id }) ERR-NOT-FOUND))
    )
    (asserts! (var-get contract-active) (err u105))
    (asserts! (is-eq (get client consultation-data) tx-sender) ERR-UNAUTHORIZED)
    (asserts! (is-eq (get status consultation-data) "completed") (err u111))
    (asserts! (and (>= client-rating u1) (<= client-rating u5)) ERR-INVALID-PARAMS)

    (map-set consultation-feedback
      { consultation-id: consultation-id }
      {
        client-rating: client-rating,
        client-comments: client-comments,
        designer-notes: "",
        follow-up-needed: follow-up-needed,
        implementation-status: "not-started"
      }
    )
    (ok true)
  )
)

;; Add consultation tokens
(define-public (add-consultation-tokens (amount uint))
  (let
    (
      (current-balance (default-to u0 (get balance (map-get? user-balances { user: tx-sender }))))
    )
    (asserts! (var-get contract-active) (err u105))
    (asserts! (> amount u0) ERR-INVALID-PARAMS)

    (map-set user-balances
      { user: tx-sender }
      { balance: (+ current-balance amount) }
    )
    (ok true)
  )
)

;; Read-only Functions

;; Get consultation information
(define-read-only (get-consultation-info (consultation-id uint))
  (map-get? design-consultations { consultation-id: consultation-id })
)

;; Get designer information
(define-read-only (get-designer-info (designer-id uint))
  (map-get? landscape-designers { designer-id: designer-id })
)

;; Get design recommendation
(define-read-only (get-recommendation (consultation-id uint) (recommendation-id uint))
  (map-get? design-recommendations { consultation-id: consultation-id, recommendation-id: recommendation-id })
)

;; Get consultation feedback
(define-read-only (get-consultation-feedback (consultation-id uint))
  (map-get? consultation-feedback { consultation-id: consultation-id })
)

;; Get user balance
(define-read-only (get-user-balance (user principal))
  (default-to u0 (get balance (map-get? user-balances { user: user })))
)

;; Get designer earnings
(define-read-only (get-designer-earnings (designer principal))
  (default-to u0 (get earnings (map-get? designer-earnings { designer: designer })))
)

;; Get total consultations
(define-read-only (get-total-consultations)
  (var-get total-consultations)
)

;; Get total designers
(define-read-only (get-total-designers)
  (var-get total-designers)
)

;; Get consultation fee
(define-read-only (get-consultation-fee)
  (var-get consultation-fee)
)

;; Administrative Functions

;; Update consultation fee
(define-public (set-consultation-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (> new-fee u0) ERR-INVALID-PARAMS)
    (var-set consultation-fee new-fee)
    (ok true)
  )
)

;; Toggle contract active state
(define-public (toggle-contract-active)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (var-set contract-active (not (var-get contract-active)))
    (ok (var-get contract-active))
  )
)
