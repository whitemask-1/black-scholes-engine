let implied_volatility ?(option_type="call") ?(tol=1e-6) ?(max_iter=100) market_price s k t r =
  let sigma = ref 0.2 in
  let result = ref None in
  let i = ref 0 in
  while !i < max_iter && !result = None do
    let price = if option_type = "call"
      then Pricing.bs_call s k t !sigma r
      else Pricing.bs_put s k t !sigma r
    in
    let v = Greeks.vega s k t r !sigma in
    if v < 1e-10 then
      result := None
    else begin
      sigma := !sigma -. (price -. market_price) /. v;
      if abs_float (price -. market_price) < tol then
        result := Some !sigma
    end;
    i := !i + 1
  done;
  !result
