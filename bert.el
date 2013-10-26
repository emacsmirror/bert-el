(require 'bindat)

(setq bert-spec
      `((tag u8)
        (union (tag)
               (97  (integer u8))
               (98  (integer u32))
               (99  (float-string str 31))
               (100 (length u16)
                    (atom-name str (length)))
               (104 (arity u8)
                    (elements repeat (arity)
                              (struct bert-spec)))
               (105 (arity u32)
                    (elements repeat (arity)
                              (struct bert-spec)))
               (106)
               (107 (length u16)
                    (characters str (length)))
               (108 (length u32)
                    (elements repeat (length)
                              (struct bert-spec))
                    (tail struct bert-spec))
               (109 (length u32)
                    (data vec (length)))
               (110 (length u8)
                    (sign u8)
                    (digits vec (length)))
               (111 (length u32)
                    (sign u8)
                    (digits vec (length))))))

(defun bert-pack (obj)
  (bindat-pack (cons (list 'magic 'u8) bert-spec)
               (cons (cons 'magic 131) (bert-encode obj))))

(defun bert-encode (obj)
  (cond ((integerp obj) (bert-encode-integer obj))
        ((floatp   obj) (bert-encode-float   obj))
        ((symbolp  obj) (bert-encode-symbol  obj))
        ((listp    obj) (bert-encode-list    obj))
        ((vectorp  obj) (bert-encode-vector  obj))
        ((stringp  obj) (bert-encode-string  obj))
        (t (error "cannot encode %S" obj))))

(defun bert-encode-integer (integer)
  `((tag . ,(if (and (>= integer 0) (< integer 256)) 97 98))
    (integer . ,integer)))

(defun bert-pad-right (string width char)
  (concat string
          (make-string (max 0 (- width (length string))) char)))

(defun bert-encode-float (float)
  (let ((float-string (bert-pad-right (format "%15.15e" float) 31 ?\000)))
    `((tag . 99)
      (float-string . ,float-string))))

(defun bert-encode-symbol (symbol)
  (let ((atom-name (symbol-name sym)))
    `((tag . 100)
      (length . ,(length atom-name))
      (atom-name . ,atom-name))))

(defun bert-encode-vector (data)
  `((tag . ,(if (< (length data) 256) 104 105))
    (arity . ,(length data))
    (elements . ,(mapcar #'bert-encode data))))

(defun bert-encode-list (list)
  (if (null list)
      `((tag . 106))
    `((tag . 108)
      (length . ,(length list))
      (elements . ,(mapcar #'bert-encode list))
      (tail . ((tag . 106))))))

(defun bert-encode-string (string)
  `((tag . 109)
    (length . ,(length string))
    (data . ,(string-to-vector string))))

(defun bert-unpack (string)
  (let* ((struct (bindat-unpack (cons (list 'magic 'u8) bert-spec) string))
         (magic (bindat-get-field struct 'magic)))
    (assert (= magic 131) t "bad magic: %d" magic)
    (bert-decode struct)))

(defun bert-decode (struct)
  (case (bindat-get-field struct 'tag)
    (97  (bert-decode-small-integer struct))
    (98  (bert-decode-integer struct))
    (99  (bert-decode-float struct))
    (100 (bert-decode-atom struct))
    ((104 105) (bert-decode-tuple struct))
    (106 nil)
    (107 (bert-decode-string struct))
    (108 (bert-decode-list struct))
    (109 (bert-decode-binary struct))
    ((110 111) (error "cannot decode bignums"))))

(defun bert-decode-small-integer (struct)
  (bindat-get-field struct 'integer))

(defun bert-decode-integer (struct)
  (let ((integer (bindat-get-field struct 'integer)))
    (if (oddp (ash integer -31))
        (- integer (ash 1 32))
      integer)))

(defun bert-decode-float (struct)
  (read (bindat-get-field struct 'float-string)))

(defun bert-decode-atom (struct)
  (intern (bindat-get-field struct 'atom-name)))

(defun bert-decode-tuple (struct)
  (let ((elements (bindat-get-field struct 'elements)))
    (apply #'vector (mapcar #'bert-decode elements))))

(defun bert-decode-string (struct)
  (bindat-get-field struct 'characters))

(defun bert-decode-list (struct)
  (let ((elements (bindat-get-field struct 'elements)))
    (mapcar #'bert-decode elements)))

(defun bert-decode-binary (struct)
  (map 'string #'identity (bindat-get-field struct 'data)))
