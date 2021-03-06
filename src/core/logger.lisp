(in-package :cl-user)
(defpackage mito.logger
  (:use #:cl)
  (:import-from #:alexandria
                #:delete-from-plist)
  (:export #:*mito-logger-stream*
           #:*mito-migration-logger-stream*
           #:with-sql-logging
           #:trace-sql
           #:*trace-sql-hooks*))
(in-package :mito.logger)

(defvar *mito-logger-stream* nil)

(defvar *mito-migration-logger-stream* (make-synonym-stream '*standard-output*)
  "Stream to output sql generated during migrations.")

(defmacro with-sql-logging (&body body)
  `(let ((*mito-logger-stream* *mito-migration-logger-stream*))
     ,@body))

(defun get-prev-stack ()
  (labels ((stack-call (stack)
             (let ((call (dissect:call stack)))
               (typecase call
                 (symbol call)
                 (cons
                  (when (eq (first call) :method)
                    (second call))))))
           #+sbcl
           (sbcl-package-p (package)
             (let ((name (package-name package)))
               (eql (mismatch "SB-" name) 3)))
           (system-call-p (call)
             (when call
               (let ((package (symbol-package call)))
                 (or #+sbcl (sbcl-package-p package)
                     (find (package-name package)
                           '(:common-lisp :mito.logger)
                           :test #'string=)))))
           (users-stack-p (stack)
             (let ((call (stack-call stack)))
               (and call
                    (not (system-call-p call))))))

    (loop with prev-stack = nil
          repeat 5
          for stack in (dissect:stack)
          when (users-stack-p stack)
            do (setf prev-stack stack)
          finally (return (when prev-stack
                            (stack-call prev-stack))))))

(defun default-trace-sql-hook (sql params results)
  (when *mito-logger-stream*
    (format *mito-logger-stream*
            "~&~<;; ~@; ~A (~{~S~^, ~}) [~D row~:P]~:[~;~:* | ~S~]~:>~%"
            (list sql
                  (mapcar (lambda (param)
                            (if (typep param '(simple-array (unsigned-byte 8) (*)))
                                (map 'string #'code-char param)
                                param))
                          params)
                  (length results)
                  (get-prev-stack)))))

(defvar *trace-sql-hooks* (list #'default-trace-sql-hook))

(defun trace-sql (sql params &optional results)
  (dolist (hook *trace-sql-hooks*)
    (funcall hook sql params results)))
