let bs_call s k t r sigma =
    let (d1, d2) = Core.compute_d1_d2 s k t r sigma in
    s *. Core.norm_cdf d1 -. k *. exp (-. r *. t) *. Core.norm_cdf d2

let bs_put s k t r sigma =
    let (d1, d2) = Core.compute_d1_d2 s k t r sigma in
    k *. exp(-. r *. t) *. Core.norm_cdf (-. d2) -. s *. Core.norm_cdf (-. d1)


