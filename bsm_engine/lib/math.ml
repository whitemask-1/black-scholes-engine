let pi = 4.0 *. atan 1.0
let norm_pdf x =
    exp (-0.5 *. x *. x) /. sqrt (2.0 *. pi)
let norm_cdf x =
    0.5 *. (1.0 +. Float.erf (x /. sqrt 2.0))

let bs_call s k t r sigma =
    let d1 = (log (s /. k) +. (r +. 0.5 *. sigma *. sigma) *. t)
            /. (sigma *. sqrt t) in
    let d2 = d1 -. sigma *. sqrt t in
    s *. norm_cdf d1 -. k *. exp (-. r *. t) *. norm_cdf d2
