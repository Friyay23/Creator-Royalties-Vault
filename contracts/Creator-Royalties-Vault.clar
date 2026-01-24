(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u401))
(define-constant ERR-VAULT-NOT-FOUND (err u404))
(define-constant ERR-INSUFFICIENT-BALANCE (err u402))
(define-constant ERR-INVALID-PERCENTAGE (err u403))
(define-constant ERR-ALREADY-EXISTS (err u409))
(define-constant ERR-INVALID-AMOUNT (err u400))
(define-constant ERR-VAULT-LOCKED (err u423))
(define-constant ERR-INVALID-RECIPIENT (err u422))
(define-constant ERR-STREAM-NOT-FOUND (err u424))
(define-constant ERR-STREAM-INACTIVE (err u426))
(define-constant ERR-INSUFFICIENT-STREAM-BALANCE (err u427))
(define-constant ERR-MILESTONE-NOT-FOUND (err u428))
(define-constant ERR-MILESTONE-NOT-REACHED (err u429))
(define-constant ERR-MILESTONE-ALREADY-CLAIMED (err u430))
(define-constant ERR-REFERRAL-SELF (err u431))
(define-constant ERR-ALREADY-REFERRED (err u432))
(define-constant ERR-REFERRAL-DISABLED (err u433))

(define-data-var vault-counter uint u0)
(define-data-var stream-counter uint u0)
(define-data-var milestone-counter uint u0)

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

(define-map streaming-payments
  { stream-id: uint }
  {
    vault-id: uint,
    recipient: principal,
    rate-per-block: uint,
    start-block: uint,
    end-block: uint,
    last-claimed-block: uint,
    total-streamed: uint,
    is-active: bool
  }
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

(define-public (create-streaming-payment (vault-id uint) (recipient principal) (total-amount uint) (duration-blocks uint))
  (let (
    (vault (unwrap! (map-get? vaults { vault-id: vault-id }) ERR-VAULT-NOT-FOUND))
    (new-stream-id (+ (var-get stream-counter) u1))
    (rate-per-block (/ total-amount duration-blocks))
  )
    (asserts! (is-eq tx-sender (get creator vault)) ERR-UNAUTHORIZED)
    (asserts! (get is-active vault) ERR-VAULT-LOCKED)
    (asserts! (> total-amount u0) ERR-INVALID-AMOUNT)
    (asserts! (> duration-blocks u0) ERR-INVALID-AMOUNT)
    (asserts! (>= (get total-balance vault) total-amount) ERR-INSUFFICIENT-BALANCE)
    
    (map-set streaming-payments
      { stream-id: new-stream-id }
      {
        vault-id: vault-id,
        recipient: recipient,
        rate-per-block: rate-per-block,
        start-block: stacks-block-height,
        end-block: (+ stacks-block-height duration-blocks),
        last-claimed-block: stacks-block-height,
        total-streamed: u0,
        is-active: true
      }
    )
    
    (map-set vaults
      { vault-id: vault-id }
      (merge vault { total-balance: (- (get total-balance vault) total-amount) })
    )
    
    (var-set stream-counter new-stream-id)
    (ok new-stream-id)
  )
)

(define-read-only (calculate-available-stream (stream-id uint))
  (match (map-get? streaming-payments { stream-id: stream-id })
    stream-data
      (let (
        (current-block stacks-block-height)
        (last-claimed (get last-claimed-block stream-data))
        (end-block (get end-block stream-data))
        (rate (get rate-per-block stream-data))
        (effective-end (if (<= current-block end-block) current-block end-block))
        (blocks-since-claim (if (> effective-end last-claimed) (- effective-end last-claimed) u0))
      )
        (if (get is-active stream-data)
          (* rate blocks-since-claim)
          u0
        )
      )
    u0
  )
)

(define-public (claim-streaming-payment (stream-id uint))
  (let (
    (stream-data (unwrap! (map-get? streaming-payments { stream-id: stream-id }) ERR-STREAM-NOT-FOUND))
    (available-amount (calculate-available-stream stream-id))
  )
    (asserts! (is-eq tx-sender (get recipient stream-data)) ERR-UNAUTHORIZED)
    (asserts! (get is-active stream-data) ERR-STREAM-INACTIVE)
    (asserts! (> available-amount u0) ERR-INSUFFICIENT-STREAM-BALANCE)
    
    (try! (as-contract (stx-transfer? available-amount tx-sender tx-sender)))
    
    (map-set streaming-payments
      { stream-id: stream-id }
      (merge stream-data 
        {
          last-claimed-block: (if (<= stacks-block-height (get end-block stream-data))
                               stacks-block-height
                               (get end-block stream-data)),
          total-streamed: (+ (get total-streamed stream-data) available-amount)
        }
      )
    )
    
    (ok available-amount)
  )
)

(define-read-only (get-streaming-payment (stream-id uint))
  (map-get? streaming-payments { stream-id: stream-id })
)

(define-map milestones
  { milestone-id: uint }
  {
    vault-id: uint,
    title: (string-ascii 128),
    target-value: uint,
    current-value: uint,
    reward-amount: uint,
    is-claimed: bool,
    created-at: uint
  }
)

(define-public (create-milestone (vault-id uint) (title (string-ascii 128)) (target-value uint) (reward-amount uint))
  (let (
    (vault (unwrap! (map-get? vaults { vault-id: vault-id }) ERR-VAULT-NOT-FOUND))
    (new-milestone-id (+ (var-get milestone-counter) u1))
  )
    (asserts! (is-eq tx-sender (get creator vault)) ERR-UNAUTHORIZED)
    (asserts! (> target-value u0) ERR-INVALID-AMOUNT)
    (asserts! (> reward-amount u0) ERR-INVALID-AMOUNT)
    (asserts! (>= (get total-balance vault) reward-amount) ERR-INSUFFICIENT-BALANCE)
    
    (map-set milestones
      { milestone-id: new-milestone-id }
      {
        vault-id: vault-id,
        title: title,
        target-value: target-value,
        current-value: u0,
        reward-amount: reward-amount,
        is-claimed: false,
        created-at: stacks-block-height
      }
    )
    
    (map-set vaults
      { vault-id: vault-id }
      (merge vault { total-balance: (- (get total-balance vault) reward-amount) })
    )
    
    (var-set milestone-counter new-milestone-id)
    (ok new-milestone-id)
  )
)

(define-public (update-milestone-progress (milestone-id uint) (new-value uint))
  (let (
    (milestone-data (unwrap! (map-get? milestones { milestone-id: milestone-id }) ERR-MILESTONE-NOT-FOUND))
    (vault (unwrap! (map-get? vaults { vault-id: (get vault-id milestone-data) }) ERR-VAULT-NOT-FOUND))
  )
    (asserts! (is-eq tx-sender (get creator vault)) ERR-UNAUTHORIZED)
    (asserts! (not (get is-claimed milestone-data)) ERR-MILESTONE-ALREADY-CLAIMED)
    
    (map-set milestones
      { milestone-id: milestone-id }
      (merge milestone-data { current-value: new-value })
    )
    
    (ok true)
  )
)

(define-public (claim-milestone-reward (milestone-id uint))
  (let (
    (milestone-data (unwrap! (map-get? milestones { milestone-id: milestone-id }) ERR-MILESTONE-NOT-FOUND))
    (vault (unwrap! (map-get? vaults { vault-id: (get vault-id milestone-data) }) ERR-VAULT-NOT-FOUND))
    (reward (get reward-amount milestone-data))
  )
    (asserts! (is-eq tx-sender (get creator vault)) ERR-UNAUTHORIZED)
    (asserts! (not (get is-claimed milestone-data)) ERR-MILESTONE-ALREADY-CLAIMED)
    (asserts! (>= (get current-value milestone-data) (get target-value milestone-data)) ERR-MILESTONE-NOT-REACHED)
    
    (map-set milestones
      { milestone-id: milestone-id }
      (merge milestone-data { is-claimed: true })
    )
    
    (map-set vaults
      { vault-id: (get vault-id milestone-data) }
      (merge vault { total-balance: (+ (get total-balance vault) reward) })
    )
    
    (ok reward)
  )
)

(define-read-only (get-milestone-info (milestone-id uint))
  (map-get? milestones { milestone-id: milestone-id })
)

(define-read-only (check-milestone-reached (milestone-id uint))
  (match (map-get? milestones { milestone-id: milestone-id })
    milestone-data (some (>= (get current-value milestone-data) (get target-value milestone-data)))
    none)
)

(define-read-only (get-milestone-counter)
  (var-get milestone-counter)
)

(define-map referral-programs
  { vault-id: uint }
  {
    reward-percentage: uint,
    is-enabled: bool,
    total-referrals: uint,
    total-rewards-paid: uint
  }
)

(define-map referrals
  { vault-id: uint, referred-user: principal }
  {
    referrer: principal,
    deposit-amount: uint,
    reward-paid: uint,
    referred-at: uint
  }
)

(define-map referrer-stats
  { vault-id: uint, referrer: principal }
  {
    total-referred: uint,
    total-rewards: uint
  }
)

(define-public (enable-referral-program (vault-id uint) (reward-percentage uint))
  (let (
    (vault (unwrap! (map-get? vaults { vault-id: vault-id }) ERR-VAULT-NOT-FOUND))
  )
    (asserts! (is-eq tx-sender (get creator vault)) ERR-UNAUTHORIZED)
    (asserts! (is-valid-percentage reward-percentage) ERR-INVALID-PERCENTAGE)
    
    (map-set referral-programs
      { vault-id: vault-id }
      {
        reward-percentage: reward-percentage,
        is-enabled: true,
        total-referrals: u0,
        total-rewards-paid: u0
      }
    )
    
    (ok true)
  )
)

(define-public (disable-referral-program (vault-id uint))
  (let (
    (vault (unwrap! (map-get? vaults { vault-id: vault-id }) ERR-VAULT-NOT-FOUND))
    (program (unwrap! (map-get? referral-programs { vault-id: vault-id }) ERR-VAULT-NOT-FOUND))
  )
    (asserts! (is-eq tx-sender (get creator vault)) ERR-UNAUTHORIZED)
    
    (map-set referral-programs
      { vault-id: vault-id }
      (merge program { is-enabled: false })
    )
    
    (ok true)
  )
)

(define-public (deposit-with-referral (vault-id uint) (referrer principal) (amount uint))
  (let (
    (vault (unwrap! (map-get? vaults { vault-id: vault-id }) ERR-VAULT-NOT-FOUND))
    (program (unwrap! (map-get? referral-programs { vault-id: vault-id }) ERR-REFERRAL-DISABLED))
    (reward-amount (/ (* amount (get reward-percentage program)) u10000))
    (existing-referrer-stats (default-to { total-referred: u0, total-rewards: u0 }
      (map-get? referrer-stats { vault-id: vault-id, referrer: referrer })))
  )
    (asserts! (get is-enabled program) ERR-REFERRAL-DISABLED)
    (asserts! (get is-active vault) ERR-VAULT-LOCKED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (not (is-eq tx-sender referrer)) ERR-REFERRAL-SELF)
    (asserts! (is-none (map-get? referrals { vault-id: vault-id, referred-user: tx-sender })) ERR-ALREADY-REFERRED)
    (asserts! (>= (get total-balance vault) reward-amount) ERR-INSUFFICIENT-BALANCE)
    
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
    
    (map-set referrals
      { vault-id: vault-id, referred-user: tx-sender }
      {
        referrer: referrer,
        deposit-amount: amount,
        reward-paid: reward-amount,
        referred-at: stacks-block-height
      }
    )
    
    (map-set referrer-stats
      { vault-id: vault-id, referrer: referrer }
      {
        total-referred: (+ (get total-referred existing-referrer-stats) u1),
        total-rewards: (+ (get total-rewards existing-referrer-stats) reward-amount)
      }
    )
    
    (map-set referral-programs
      { vault-id: vault-id }
      (merge program {
        total-referrals: (+ (get total-referrals program) u1),
        total-rewards-paid: (+ (get total-rewards-paid program) reward-amount)
      })
    )
    
    (map-set vaults
      { vault-id: vault-id }
      (merge vault { total-balance: (- (+ (get total-balance vault) amount) reward-amount) })
    )
    
    (try! (as-contract (stx-transfer? reward-amount tx-sender referrer)))
    
    (ok { deposit: amount, referral-reward: reward-amount })
  )
)

(define-read-only (get-referral-program (vault-id uint))
  (map-get? referral-programs { vault-id: vault-id })
)

(define-read-only (get-referral-info (vault-id uint) (referred-user principal))
  (map-get? referrals { vault-id: vault-id, referred-user: referred-user })
)

(define-read-only (get-referrer-stats (vault-id uint) (referrer principal))
  (map-get? referrer-stats { vault-id: vault-id, referrer: referrer })
)
