#lang racket/base
(provide
  record
  records
  record-struct
  )

(require (for-syntax racket/base))
(require (for-syntax racket/list))
(require racket/dict)
(require racket/list)
(require racket/match)

(define-syntax record-struct
  (syntax-rules ()
    ((_ name (field ...) struct-rest ...)
     (struct name (field ...) #:transparent
      #:methods gen:dict
      ((define (dict-ref rec . rest)
         (match rec
           ((name field ...)
            (apply hash-ref
                   (cons (record-hash field ...) rest)))))
       (define (dict-set rec key val)
         (match rec
           ((name field ...)
            (let ((temp (hash-set (record-hash field ...) key val)))
              (name (hash-ref temp 'field) ...)))))
       (define (dict-iterate-first rec)
         (if (empty? '(field ...)) #f 0))
       (define (dict-iterate-next rec pos)
         (let ((next (+ pos 1)))
           (if (< next (length '(field ...))) next #f)))
       (define (dict-iterate-key rec pos)
         (list-ref '(field ...) pos))
       (define (dict-iterate-value rec pos)
         (match rec
           ((name field ...) (list-ref (list field ...) pos))))
       (define (dict-count rec)
         (length '(field ...))))
      struct-rest ...))))

(define-syntax record
  (syntax-rules ()
    ((_ name field ...) (record-struct name (field ...)))))

(define-syntax (records stx)
  (syntax-case stx ()
    ((_ name (rname rfield ...) ...)
     #`(begin
         (define (#,(identifier-with-? #'name) datum)
           (or
             #,@(map
                  (lambda (ident)
                    (list (identifier-with-? ident) #'datum))
                  (syntax->list #'(rname ...)))))
         (record rname rfield ...) ...))))

(define-syntax (record-hash stx)
  (syntax-case stx ()
    ((_ field ...)
     (let ((kvs (flatten (map syntax->list
                              (syntax->list #'(('field field) ...))))))
       #`(hash #,@kvs)))))

(define-for-syntax (identifier-with-? ident)
  (datum->syntax
    ident
    (string->symbol
      (string-append (symbol->string (syntax->datum ident))
                     "?"))))