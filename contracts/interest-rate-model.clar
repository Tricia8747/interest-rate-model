;; interest-rate-model.clar
;; Utilization-based interest rate model (dual-slope / kink) for lending markets on Stacks (STX)
;; - Rates expressed in BPS (basis points, 1 BPS = 0.01%)
;; - Useful for lending protocols to compute borrow + supply rates.
;; - Admin-configurable parameters.

(define-constant BPS u10000)
;; Approx blocks per year; adjust to your chain estimate (Stacks ~ 10s/block -> ~3,153,600)
(define-constant BLOCKS_PER_YEAR u3153600)

;; Errors
(define-constant ERR_NOT_ADMIN u100)
(define-constant ERR_BAD_PARAM u101)
(define-constant ERR_MATH u102)

;; Admin
(define-data-var admin principal tx-sender)

;; Model parameters (all uint in BPS unless noted)
;; base-rate-per-year-bps: baseline borrow APR (bps/year)
(define-data-var base-rate-per-year-bps uint u200)         ;; default 2.00% APR

;; multiplier-per-year-bps: slope before kink (bps per 1.0 utilization)
(define-data-var multiplier-per-year-bps uint u2000)      ;; default 20.00% APR at full utilization

;; jump-multiplier-per-year-bps: slope after kink (bps per 1.0 utilization)
(define-data-var jump-multiplier-per-year-bps uint u10000) ;; steeper slope after kink

;; kink (utilization threshold) expressed in BPS (0..10000). e.g., 8000 => 80%
(define-data-var kink-bps uint u8000)

;; reserve-factor-bps: portion of interest set aside as reserves (0..10000)
(define-data-var reserve-factor-bps uint u1000) ;; default 10% reserves

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Admin setters
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-public (set-admin (p principal))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err ERR_NOT_ADMIN))
    ;; Add explicit check to ensure p is not null
    (asserts! (not (is-eq p (var-get admin))) (err ERR_BAD_PARAM))
    (var-set admin p)
    (ok true)))

(define-public (set-base-rate (bps-per-year uint))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err ERR_NOT_ADMIN))
    (asserts! (<= bps-per-year BPS) (err ERR_BAD_PARAM))
    (var-set base-rate-per-year-bps bps-per-year)
    (ok true)))

(define-public (set-multiplier (bps-per-year uint))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err ERR_NOT_ADMIN))
    ;; Add safety check for multiplier
    (asserts! (> bps-per-year u0) (err ERR_BAD_PARAM))
    (var-set multiplier-per-year-bps bps-per-year)
    (ok true)))

(define-public (set-jump-multiplier (bps-per-year uint))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err ERR_NOT_ADMIN))
    ;; Add safety check for jump multiplier
    (asserts! (> bps-per-year u0) (err ERR_BAD_PARAM))
    (var-set jump-multiplier-per-year-bps bps-per-year)
    (ok true)))

(define-public (set-kink (new-kink-bps uint))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err ERR_NOT_ADMIN))
    (asserts! (<= new-kink-bps BPS) (err ERR_BAD_PARAM))
    (var-set kink-bps new-kink-bps)
    (ok true)))

(define-public (set-reserve-factor (rf-bps uint))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err ERR_NOT_ADMIN))
    (asserts! (<= rf-bps BPS) (err ERR_BAD_PARAM))
    (var-set reserve-factor-bps rf-bps)
    (ok true)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Core math views
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; get-utilization: given total-cash, total-borrows, total-reserves (all uint micro-units)
;; returns utilization as BPS (0..10000)
(define-read-only (get-utilization (total-cash uint) (total-borrows uint) (total-reserves uint))
  (let ((available (if (> total-cash total-reserves) (- total-cash total-reserves) u0))
        (borrows total-borrows))
    (if (is-eq (+ borrows available) u0)
        (ok u0)
        (ok (/ (* borrows BPS) (+ borrows available))))))

;; compute borrow rate (bps per year) according to dual-slope model
(define-read-only (get-borrow-rate-per-year-bps (util-bps uint))
  (let ((base (var-get base-rate-per-year-bps))
        (mult (var-get multiplier-per-year-bps))
        (jump (var-get jump-multiplier-per-year-bps))
        (kink (var-get kink-bps)))
    (asserts! (<= util-bps BPS) (err ERR_BAD_PARAM))
    (let ((util util-bps))
      (if (<= util kink)
          ;; rate = base + util/kink * mult   ; but we want util * mult / BPS
          (ok (+ base (/ (* util mult) BPS)))
          ;; rate = base + kink*mult/BPS + (util - kink) * jump / BPS
          (ok (+ base (/ (* kink mult) BPS) (/ (* (- util kink) jump) BPS)))))))

;; borrow rate per block (bps per block) = borrow-bps-per-year / BLOCKS_PER_YEAR (integer division)
(define-read-only (get-borrow-rate-per-block-bps (util-bps uint))
  (let ((byear (unwrap-panic (get-borrow-rate-per-year-bps util-bps))))
    (ok (/ byear BLOCKS_PER_YEAR))))

;; supply rate per year (bps) = borrowRate * utilization * (1 - reserveFactor)
;; All in integer BPS arithmetic:
;; supplyBps = borrowBps * util_bps * (BPS - reserveFactor) / (BPS * BPS)
(define-read-only (get-supply-rate-per-year-bps (util-bps uint))
  (let ((borrow-bps (unwrap-panic (get-borrow-rate-per-year-bps util-bps)))
        (rf (var-get reserve-factor-bps)))
    (ok (/ (* borrow-bps util-bps (- BPS rf)) (* BPS BPS)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Convenience: compute borrow+supply rates from market state
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Given total-cash, total-borrows, total-reserves, return
;; { utilization: util-bps, borrow-per-year-bps: bps, borrow-per-block-bps: bpsPerBlock, supply-per-year-bps: bps }
(define-read-only (rates-from-market (total-cash uint) (total-borrows uint) (total-reserves uint))
  (let ((util (unwrap-panic (get-utilization total-cash total-borrows total-reserves))))
    (let ((borrow-yr (unwrap-panic (get-borrow-rate-per-year-bps util)))
          (borrow-block (unwrap-panic (get-borrow-rate-per-block-bps util)))
          (supply-yr (unwrap-panic (get-supply-rate-per-year-bps util))))
      (ok { utilization: util, borrow_rate_per_year_bps: borrow-yr, borrow_rate_per_block_bps: borrow-block, supply_rate_per_year_bps: supply-yr }))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Read-only getters for parameters
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define-read-only (get-params)
  (ok {
    base_rate_per_year_bps: (var-get base-rate-per-year-bps),
    multiplier_per_year_bps: (var-get multiplier-per-year-bps),
    jump_multiplier_per_year_bps: (var-get jump-multiplier-per-year-bps),
    kink_bps: (var-get kink-bps),
    reserve_factor_bps: (var-get reserve-factor-bps),
    blocks_per_year: BLOCKS_PER_YEAR
  }))
