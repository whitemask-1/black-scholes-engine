let delta s k t r sigma option_type =
    let (d1, _) = Core.compute_d1_d2 s k t r sigma in
    if option_type = "call" then Core.norm_cdf d1
    else Core.norm_cdf d1 -. 1.0

let gamma s k t r sigma =
    let (d1, _) = Core.compute_d1_d2 s k t r sigma in
    Core.norm_pdf d1 /. (s *. sigma *. sqrt t)

let vega s k t r sigma =
    let (d1, _) = Core.compute_d1_d2 s k t r sigma in
    s *. Core.norm_pdf d1 *. sqrt t

let theta s k t r sigma option_type =
    let (d1, d2) = Core.compute_d1_d2 s k t r sigma in
    let term1 = -.(s *. Core.norm_pdf(d1) *. sigma) /. (2.0 *. sqrt t) in
    if option_type = "call" then abs_float (term1 -. r *. k *. exp (-. r *. t) *. Core.norm_cdf d2)
    else abs_float (term1 +. r *. k *. exp (-. r *. t) *. Core.norm_cdf (-. d2))

let theta_daily s k t r sigma option_type =
  theta s k t r sigma option_type /. 365.0

let rho s k t r sigma option_type =
    let (_, d2) = Core.compute_d1_d2 s k t r sigma in
    if option_type = "call" then k *. t *. exp (-. r *. t) *. Core.norm_cdf d2
    else -. k *. t *. exp (-. r *. t) *. Core.norm_cdf (-. d2)

