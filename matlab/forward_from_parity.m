function chain = forward_from_parity(chain, nNearest)
%FORWARD_FROM_PARITY Estimate the forward price F per expiry via put-call parity.
%   chain = forward_from_parity(chain)
%
%   For a strike with both a call and a put:  C - P = e^{-rT} (F - K)
%   =>  F = K + e^{rT} (C - P). The median over the nNearest (default 5)
%   strikes closest to spot is used. If an expiry has no strike with both
%   sides, F falls back to S e^{(r-q)T}. Adds columns F and fwd_src.

    if nargin < 2, nNearest = 5; end
    chain.F = nan(height(chain), 1);
    chain.fwd_src = repmat("parity", height(chain), 1);

    [g, ~] = findgroups(chain.expiry);
    for i = 1:max(g)
        idx = find(g == i);
        sub = chain(idx, :);
        S = sub.spot(1);  T = sub.tau(1);  r = sub.r(1);  q = sub.q(1);

        c = sub(sub.type == "call", :);  p = sub(sub.type == "put", :);
        [ks, ~, ic] = unique(c.strike);  cm = accumarray(ic, c.mid, [], @mean);
        [kp, ~, ip] = unique(p.strike);  pm = accumarray(ip, p.mid, [], @mean);
        [kc, a, b] = intersect(ks, kp);

        if isempty(kc)
            F = S * exp((r - q) * T);
            chain.fwd_src(idx) = "model";
        else
            [~, order] = sort(abs(kc - S));
            use = order(1:min(nNearest, numel(order)));
            Fk = kc(use) + exp(r*T) * (cm(a(use)) - pm(b(use)));
            F = median(Fk);
        end
        chain.F(idx) = F;
    end
end
