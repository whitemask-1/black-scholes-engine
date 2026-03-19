open Bsm_engine

let () = 
    let s = float_of_string Sys.argv.(1) in
    let k = float_of_string Sys.argv.(2) in
    let t = float_of_string Sys.argv.(3) in
    let r = float_of_string Sys.argv.(4) in
    let market_price = float_of_string Sys.argv.(5) in
    let option_type = Sys.argv.(6) in
    let iv_fn = if option_type = "call" then Volatility.iv_call else Volatility.iv_put in
    match iv_fn market_price s k t r with
    | None -> Printf.printf "{\"error\": \"iv_failed\"}\n"
    | Some iv ->
        Printf.printf
            {|{"strike":%.6f,"call":%.6f,"put":%.6f,"delta":%.6f,"gamma":%.6f,"vega":%.6f,"theta":%.6f,"theta_daily":%.6f,"rho":%.6f,"iv":%.6f}|}
            k
            (Pricing.bs_call s k t r iv)
            (Pricing.bs_put s k t r iv)
            (Greeks.delta s k t r iv option_type)
            (Greeks.gamma s k t r iv)
            (Greeks.vega s k t r iv)
            (Greeks.theta s k t r iv option_type)
            (Greeks.theta_daily s k t r iv option_type)
            (Greeks.rho s k t r iv option_type)
            iv
