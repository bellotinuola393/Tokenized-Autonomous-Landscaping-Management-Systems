;; Lawn Care Scheduling Contract
;; Coordinates mowing and maintenance services

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-OWNER-ONLY (err u100))
(define-constant ERR-NOT-FOUND (err u101))
(define-constant ERR-INVALID-PARAMS (err u102))
(define-constant ERR-INSUFFICIENT-BALANCE (err u103))
(define-constant ERR-UNAUTHORIZED (err u104))

;; Data Variables
(define-data-var contract-active bool true)
(define-data-var total-properties uint u0)
(define-data-var total-providers uint u0)
(define-data-var service-token-price uint u50)

;; Data Maps
(define-map properties
  { property-id: uint }
  {
    owner: principal,
    address: (string-ascii 200),
    lawn-size: uint,
    grass-type: (string-ascii 50),
    mowing-frequency: uint,
    last-service: uint,
    next-service: uint,
    active: bool
  }
)

(define-map service-providers
  { provider-id: uint }
  {
    provider: principal,
    name: (string-ascii 100),
    services-offered: (string-ascii 200),
    reputation-score: uint,
    total-jobs: uint,
    active: bool
  }
)

(define-map service-requests
  { request-id: uint }
  {
    property-id: uint,
    service-type: (string-ascii 50),
    requested-date: uint,
    assigned-provider: uint,
    status: (string-ascii 20),
    completion-date: uint,
    quality-rating: uint
  }
)

(define-map user-balances
  { user: principal }
  { balance: uint }
)

(define-map provider-earnings
  { provider: principal }
  { earnings: uint }
)

;; Private Variables
(define-data-var next-request-id uint u1)

;; Public Functions

;; Register a new property
(define-public (register-property (address (string-ascii 200)) (lawn-size uint) (grass-type (string-ascii 50)) (mowing-frequency uint))
  (let
    (
      (property-id (+ (var-get total-properties) u1))
    )
    (asserts! (var-get contract-active) (err u105))
    (asserts! (> (len address) u0) ERR-INVALID-PARAMS)
    (asserts! (> lawn-size u0) ERR-INVALID-PARAMS)
    (asserts! (> mowing-frequency u0) ERR-INVALID-PARAMS)

    (map-set properties
      { property-id: property-id }
      {
        owner: tx-sender,
        address: address,
        lawn-size: lawn-size,
        grass-type: grass-type,
        mowing-frequency: mowing-frequency,
        last-service: u0,
        next-service: (+ block-height mowing-frequency),
        active: true
      }
    )
    (var-set total-properties property-id)
    (ok property-id)
  )
)

;; Register as a service provider
(define-public (register-provider (name (string-ascii 100)) (services-offered (string-ascii 200)))
  (let
    (
      (provider-id (+ (var-get total-providers) u1))
    )
    (asserts! (var-get contract-active) (err u105))
    (asserts! (> (len name) u0) ERR-INVALID-PARAMS)

    (map-set service-providers
      { provider-id: provider-id }
      {
        provider: tx-sender,
        name: name,
        services-offered: services-offered,
        reputation-score: u50,
        total-jobs: u0,
        active: true
      }
    )
    (var-set total-providers provider-id)
    (ok provider-id)
  )
)

;; Create a service request
(define-public (create-service-request (property-id uint) (service-type (string-ascii 50)) (requested-date uint))
  (let
    (
      (property-data (unwrap! (map-get? properties { property-id: property-id }) ERR-NOT-FOUND))
      (request-id (var-get next-request-id))
      (service-cost (* (get lawn-size property-data) (var-get service-token-price)))
      (user-balance (default-to u0 (get balance (map-get? user-balances { user: tx-sender }))))
    )
    (asserts! (var-get contract-active) (err u105))
    (asserts! (is-eq (get owner property-data) tx-sender) ERR-UNAUTHORIZED)
    (asserts! (get active property-data) (err u106))
    (asserts! (>= user-balance service-cost) ERR-INSUFFICIENT-BALANCE)
    (asserts! (> (len service-type) u0) ERR-INVALID-PARAMS)

    ;; Deduct service tokens
    (map-set user-balances
      { user: tx-sender }
      { balance: (- user-balance service-cost) }
    )

    (map-set service-requests
      { request-id: request-id }
      {
        property-id: property-id,
        service-type: service-type,
        requested-date: requested-date,
        assigned-provider: u0,
        status: "pending",
        completion-date: u0,
        quality-rating: u0
      }
    )

    (var-set next-request-id (+ request-id u1))
    (ok request-id)
  )
)

;; Assign provider to service request
(define-public (assign-provider (request-id uint) (provider-id uint))
  (let
    (
      (request-data (unwrap! (map-get? service-requests { request-id: request-id }) ERR-NOT-FOUND))
      (provider-data (unwrap! (map-get? service-providers { provider-id: provider-id }) ERR-NOT-FOUND))
    )
    (asserts! (var-get contract-active) (err u105))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (get active provider-data) (err u107))
    (asserts! (is-eq (get status request-data) "pending") (err u108))

    (map-set service-requests
      { request-id: request-id }
      (merge request-data {
        assigned-provider: provider-id,
        status: "assigned"
      })
    )
    (ok true)
  )
)

;; Complete service request
(define-public (complete-service (request-id uint))
  (let
    (
      (request-data (unwrap! (map-get? service-requests { request-id: request-id }) ERR-NOT-FOUND))
      (provider-data (unwrap! (map-get? service-providers { provider-id: (get assigned-provider request-data) }) ERR-NOT-FOUND))
      (property-data (unwrap! (map-get? properties { property-id: (get property-id request-data) }) ERR-NOT-FOUND))
    )
    (asserts! (var-get contract-active) (err u105))
    (asserts! (is-eq (get provider provider-data) tx-sender) ERR-UNAUTHORIZED)
    (asserts! (is-eq (get status request-data) "assigned") (err u109))

    ;; Update request status
    (map-set service-requests
      { request-id: request-id }
      (merge request-data {
        status: "completed",
        completion-date: block-height
      })
    )

    ;; Update property last service
    (map-set properties
      { property-id: (get property-id request-data) }
      (merge property-data {
        last-service: block-height,
        next-service: (+ block-height (get mowing-frequency property-data))
      })
    )

    ;; Update provider stats
    (map-set service-providers
      { provider-id: (get assigned-provider request-data) }
      (merge provider-data {
        total-jobs: (+ (get total-jobs provider-data) u1)
      })
    )

    (ok true)
  )
)

;; Rate completed service
(define-public (rate-service (request-id uint) (rating uint))
  (let
    (
      (request-data (unwrap! (map-get? service-requests { request-id: request-id }) ERR-NOT-FOUND))
      (property-data (unwrap! (map-get? properties { property-id: (get property-id request-data) }) ERR-NOT-FOUND))
    )
    (asserts! (var-get contract-active) (err u105))
    (asserts! (is-eq (get owner property-data) tx-sender) ERR-UNAUTHORIZED)
    (asserts! (is-eq (get status request-data) "completed") (err u110))
    (asserts! (and (>= rating u1) (<= rating u5)) ERR-INVALID-PARAMS)

    (map-set service-requests
      { request-id: request-id }
      (merge request-data { quality-rating: rating })
    )
    (ok true)
  )
)

;; Add service tokens
(define-public (add-service-tokens (amount uint))
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

;; Get property information
(define-read-only (get-property-info (property-id uint))
  (map-get? properties { property-id: property-id })
)

;; Get service provider information
(define-read-only (get-provider-info (provider-id uint))
  (map-get? service-providers { provider-id: provider-id })
)

;; Get service request information
(define-read-only (get-service-request (request-id uint))
  (map-get? service-requests { request-id: request-id })
)

;; Get user balance
(define-read-only (get-user-balance (user principal))
  (default-to u0 (get balance (map-get? user-balances { user: user })))
)

;; Check if property needs service
(define-read-only (needs-service (property-id uint))
  (match (map-get? properties { property-id: property-id })
    property-data
    (>= block-height (get next-service property-data))
    false
  )
)

;; Get total properties
(define-read-only (get-total-properties)
  (var-get total-properties)
)

;; Get total providers
(define-read-only (get-total-providers)
  (var-get total-providers)
)

;; Administrative Functions

;; Toggle contract active state
(define-public (toggle-contract-active)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (var-set contract-active (not (var-get contract-active)))
    (ok (var-get contract-active))
  )
)

;; Update service token price
(define-public (set-service-token-price (new-price uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (> new-price u0) ERR-INVALID-PARAMS)
    (var-set service-token-price new-price)
    (ok true)
  )
)
