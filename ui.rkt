#lang racket/base
(provide
  dispatch-event-sources
  dispatch-events
  dispatch-react-loop
  event-keycount
  event-keypress
  event-terminate
  event-tick
  keycount-controller
  keymap-controller
  keypress-event-source
  latency-default
  markout-dispatch-react-loop
  note-terminated
  note-view
  terminal-event-sources
  tick-event-source
  )

(require
  "dict.rkt"
  "either.rkt"
  "markout.rkt"
  "maybe.rkt"
  "monad.rkt"
  "record.rkt"
  "sugar.rkt"
  "terminal.rkt"
  racket/list
  racket/match
  )

(module+ test
  (require rackunit))

(records base-event
  (event-terminate signal)
  (event-tick dt)
  (event-keypress char)
  (event-keycount char count))

(records base-note
  (note-terminated result)
  (note-view view))

(define latency-default 0.1)

(define (tick-event-source dt) (list (event-tick dt)))
(define (keypress-event-source dt) (map event-keypress (read-chars-ready)))
(define terminal-event-sources (list tick-event-source keypress-event-source))

(define (dispatch-fold f ctrl xs)
  (forf
    (list ctrl notes) = (list ctrl '())
    x <- xs
    (list ctrl new-notes) = (f ctrl x)
    (list ctrl (append notes new-notes))))
(define (dispatch-events ctrl events)
  (dispatch-fold (lambda (ctrl event) (ctrl event)) ctrl events))
(define (dispatch-event-sources ctrl sources dt)
  (dispatch-fold (lambda (ctrl source) (dispatch-events ctrl (source dt)))
                 ctrl sources))
(define (dispatch-react-loop react ctrl sources (latency latency-default))
  (def (loop react ctrl prev-start)
    start = (current-milliseconds)
    dt = (- start prev-start)
    (list ctrl notes) = (dispatch-event-sources ctrl sources dt)
    (match (react notes)
      ((right react)
       (lets
         overhead = (- (current-milliseconds) start)
         sleep-duration = (/ (max 0 (- (* latency 1000) overhead)) 1000)
         _ = (sleep sleep-duration)
         (loop react ctrl start)))
      ((left result) result)))
  (loop react ctrl (current-milliseconds)))

(module+ test
  (def (tick-ctrl (event-tick dt)) (list tick-ctrl (list (note-view dt))))
  (check-equal?
    (dispatch-event-sources
      tick-ctrl (list tick-event-source tick-event-source) 12)
    (list tick-ctrl (list (note-view 12) (note-view 12)))
    ))

(define (keycount-controller sub-ctrl)
  (define (digits->count digits)
    (if (empty? digits) 1 (string->number (list->string (reverse digits)))))
  (define (keycount-controller-new digits sub-ctrl)
    (fn (event)
      (list digits sub-ctrl notes) =
      (match event
        ((event-keypress char)
         (if (char-numeric? char)
           (list (list* char digits) sub-ctrl '())
           (list* '() (sub-ctrl (event-keycount
                                  char (digits->count digits))))))
        (_ (list* digits (sub-ctrl event))))
      (list (keycount-controller-new digits sub-ctrl) notes)))
  (keycount-controller-new '() sub-ctrl))

(define (keymap-controller keymap sub-ctrl)
  (fn (event)
    (list sub-ctrl notes) =
    (match event
      ((event-keycount char count)
       (match (dict-get keymap char)
         ((just action) (dispatch-events sub-ctrl (action count)))
         ((nothing) (sub-ctrl event))))
      (_ (sub-ctrl event)))
    (list (keymap-controller keymap sub-ctrl) notes)))

(module+ test
  (def (identity-ctrl event) (list identity-ctrl (list (note-view event))))
  (define test-keymap
    (hash #\q (lambda (count) (list (event-terminate count)))))
  (define key-ctrl
    (keycount-controller (keymap-controller test-keymap identity-ctrl)))
  (define (test-key-source dt)
    (list (event-keypress #\4) (event-keypress #\2) (event-keypress #\q)))
  (check-equal?
    (cadr (dispatch-event-sources key-ctrl (list test-key-source) 12))
    (list (note-view (event-terminate 42)))
    ))

(def (display-doc doc)
  (size width height) = (screen-size)
  ctx = (sizing-context-new-default)
  block = (doc->styled-block ctx style-empty width doc)
  doc-str = (styled-block->string block)
  _ = (screen-clear)
  (displayln doc-str))

(define ((markout-reactor doc) notes)
  (define (handle-note doc note)
    (match note
      ((note-terminated result) (left result))
      ((note-view next-doc) (right next-doc))
      (_ (right doc))))
  (begin/with-monad either-monad
    next-doc <- (monad-foldl either-monad handle-note doc notes)
    _ = (unless (eq? doc next-doc) (display-doc next-doc))
    (pure (markout-reactor next-doc))))

(define (markout-dispatch-react-loop doc-0 ctrl (latency latency-default))
  (with-cursor-hidden
    (with-stty-direct
      (with-screen-fresh
        (display-doc doc-0)
        (dispatch-react-loop (markout-reactor doc-0)
                             ctrl terminal-event-sources latency)))))

(module+ main
  (define (doc-str str) (doc-atom style-empty str))
  (define (doc-append . docs) (vertical-list style-empty docs))
  (define ((ctrl doc) event)
    (def (note-doc-append doc-tail)
      new-doc = (doc-append doc doc-tail)
      (list (ctrl new-doc) (list (note-view new-doc))))
    (match event
      ((event-terminate _) (list (ctrl doc) (list (note-terminated (void)))))
      ((event-tick dt)
       (note-doc-append (doc-str (format "time-delta: ~ams" dt))))
      ((event-keycount char count)
       (note-doc-append (doc-str (format "keycount: ~v,~a" char count))))
      (_ (list (ctrl doc) '()))))
  (define keymap
    (hash
      #\q (fn (_) (list (event-terminate (void))))
      ))
  (lets
    sty = (style 'yellow 'blue #f #f #f #f)
    doc = (doc-preformatted (styled-block-fill sty #\x (size 10 20)))
    doc = (doc-append doc (doc-str "Press 'q' to quit this test."))
    ctrl = (keymap-controller keymap (ctrl doc))
    (markout-dispatch-react-loop doc (keycount-controller ctrl))
    ))