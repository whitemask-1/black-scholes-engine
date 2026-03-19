let () = 
    let price = Bsm_engine.Pricing.bs_call 100.0 100.0 0.25 0.05 0.2 in
    Printf.printf "BSM call price: %.4f\n" price
