(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u401))
(define-constant ERR-VAULT-NOT-FOUND (err u404))
(define-constant ERR-INSUFFICIENT-BALANCE (err u402))
(define-constant ERR-INVALID-PERCENTAGE (err u403))
(define-constant ERR-ALREADY-EXISTS (err u409))
(define-constant ERR-INVALID-AMOUNT (err u400))
(define-constant ERR-VAULT-LOCKED (err u423))
(define-constant ERR-INVALID-RECIPIENT (err u422))

(define-data-var vault-counter uint u0)

(define-map vaults 
  { vault-id: uint }
  {
    creator: principal,
    title: (string-ascii 64),
    total-balance: uint,
    locked-until: uint,
    is-active: bool
  }
)

(define-map royalty-splits
  { vault-id: uint, recipient: principal }
  {
    percentage: uint,
    total-earned: uint
  }
)

(define-map vault-deposits
  { vault-id: uint, depositor: principal }
  {
    amount: uint,
    block-height: uint
  }
)

(define-map user-vaults
  { creator: principal }
  { vault-ids: (list 50 uint) }
)

(define-private (is-valid-percentage (percentage uint))
  (and (> percentage u0) (<= percentage u10000))
)

(define-private (get-vault-recipients-list (vault-id uint))
  (default-to (list) 
    (get recipients 
      (map-get? vault-metadata { vault-id: vault-id })))
)

(define-map vault-metadata
  { vault-id: uint }
  { recipients: (list 20 principal) }
)

(define-public (create-vault (title (string-ascii 64)) (locked-blocks uint))
  (let 
    (
      (new-vault-id (+ (var-get vault-counter) u1))
    )
    (asserts! (> (len title) u0) ERR-INVALID-AMOUNT)
    (asserts! (> locked-blocks u0) ERR-INVALID-AMOUNT)
    
    (map-set vaults
      { vault-id: new-vault-id }
      {
        creator: tx-sender,
        title: title,
        total-balance: u0,
        locked-until: (+ stacks-block-height locked-blocks),
        is-active: true
      }
    )
    
    (map-set vault-metadata
      { vault-id: new-vault-id }
      { recipients: (list) }
    )
    
    (map-set user-vaults
      { creator: tx-sender }
      { 
        vault-ids: (unwrap! 
          (as-max-len? 
            (append 
              (default-to (list) 
                (get vault-ids 
                  (map-get? user-vaults { creator: tx-sender }))) 
              new-vault-id) 
            u50) 
          ERR-INVALID-AMOUNT)
      }
    )
    
    (var-set vault-counter new-vault-id)
    (ok new-vault-id)
  )
)

(define-public (add-royalty-recipient (vault-id uint) (recipient principal) (percentage uint))
  (let 
    (
      (vault (unwrap! (map-get? vaults { vault-id: vault-id }) ERR-VAULT-NOT-FOUND))
      (current-recipients (default-to (list) 
        (get recipients (map-get? vault-metadata { vault-id: vault-id }))))
    )
    (asserts! (is-eq tx-sender (get creator vault)) ERR-UNAUTHORIZED)
    (asserts! (is-valid-percentage percentage) ERR-INVALID-PERCENTAGE)
    (asserts! (is-none (map-get? royalty-splits { vault-id: vault-id, recipient: recipient })) ERR-ALREADY-EXISTS)
    (asserts! (< (len current-recipients) u20) ERR-INVALID-AMOUNT)
    
    (map-set royalty-splits
      { vault-id: vault-id, recipient: recipient }
      {
        percentage: percentage,
        total-earned: u0
      }
    )
    
    (map-set vault-metadata
      { vault-id: vault-id }
      { 
        recipients: (unwrap! 
          (as-max-len? 
            (append current-recipients recipient) 
            u20) 
          ERR-INVALID-AMOUNT)
      }
    )
    
    (ok true)
  )
)

(define-public (deposit-royalty (vault-id uint))
  (let 
    (
      (vault (unwrap! (map-get? vaults { vault-id: vault-id }) ERR-VAULT-NOT-FOUND))
      (amount (stx-get-balance tx-sender))
    )
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (get is-active vault) ERR-VAULT-LOCKED)
    
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    (map-set vaults
      { vault-id: vault-id }
      (merge vault { total-balance: (+ (get total-balance vault) amount) })
    )
    
    (map-set vault-deposits
      { vault-id: vault-id, depositor: tx-sender }
      {
        amount: (+ amount 
          (default-to u0 
            (get amount 
              (map-get? vault-deposits { vault-id: vault-id, depositor: tx-sender })))),
        block-height: stacks-block-height
      }
    )
    
    (ok amount)
  )
)

(define-public (withdraw-royalty (vault-id uint))
  (let 
    (
      (vault (unwrap! (map-get? vaults { vault-id: vault-id }) ERR-VAULT-NOT-FOUND))
      (split-info (unwrap! (map-get? royalty-splits { vault-id: vault-id, recipient: tx-sender }) ERR-UNAUTHORIZED))
      (total-balance (get total-balance vault))
      (withdrawal-amount (/ (* total-balance (get percentage split-info)) u10000))
    )
    (asserts! (> withdrawal-amount u0) ERR-INSUFFICIENT-BALANCE)
    (asserts! (>= stacks-block-height (get locked-until vault)) ERR-VAULT-LOCKED)
    
    (try! (as-contract (stx-transfer? withdrawal-amount tx-sender tx-sender)))
    
    (map-set vaults
      { vault-id: vault-id }
      (merge vault { total-balance: (- total-balance withdrawal-amount) })
    )
    
    (map-set royalty-splits
      { vault-id: vault-id, recipient: tx-sender }
      (merge split-info { total-earned: (+ (get total-earned split-info) withdrawal-amount) })
    )
    
    (ok withdrawal-amount)
  )
)

(define-public (emergency-withdraw (vault-id uint))
  (let 
    (
      (vault (unwrap! (map-get? vaults { vault-id: vault-id }) ERR-VAULT-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get creator vault)) ERR-UNAUTHORIZED)
    (asserts! (> (get total-balance vault) u0) ERR-INSUFFICIENT-BALANCE)
    
    (try! (as-contract (stx-transfer? (get total-balance vault) tx-sender tx-sender)))
    
    (map-set vaults
      { vault-id: vault-id }
      (merge vault { 
        total-balance: u0,
        is-active: false
      })
    )
    
    (ok (get total-balance vault))
  )
)

(define-public (update-vault-status (vault-id uint) (is-active bool))
  (let 
    (
      (vault (unwrap! (map-get? vaults { vault-id: vault-id }) ERR-VAULT-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get creator vault)) ERR-UNAUTHORIZED)
    
    (map-set vaults
      { vault-id: vault-id }
      (merge vault { is-active: is-active })
    )
    
    (ok true)
  )
)

(define-read-only (get-vault-info (vault-id uint))
  (map-get? vaults { vault-id: vault-id })
)

(define-read-only (get-royalty-split (vault-id uint) (recipient principal))
  (map-get? royalty-splits { vault-id: vault-id, recipient: recipient })
)

(define-read-only (get-vault-recipients (vault-id uint))
  (get recipients (map-get? vault-metadata { vault-id: vault-id }))
)

(define-read-only (get-user-vaults (creator principal))
  (get vault-ids (map-get? user-vaults { creator: creator }))
)

(define-read-only (get-deposit-info (vault-id uint) (depositor principal))
  (map-get? vault-deposits { vault-id: vault-id, depositor: depositor })
)

(define-read-only (calculate-royalty-amount (vault-id uint) (recipient principal))
  (match (map-get? vaults { vault-id: vault-id })
    vault (match (map-get? royalty-splits { vault-id: vault-id, recipient: recipient })
      split (some (/ (* (get total-balance vault) (get percentage split)) u10000))
      none)
    none)
)

(define-read-only (get-vault-counter)
  (var-get vault-counter)
)
