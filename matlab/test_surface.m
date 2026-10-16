function test_surface()
%TEST_SURFACE Checks for build_surface / slices using a surface with a KNOWN answer.
%   Run from the matlab/ folder:  test_surface
    ivTrue = @(k, t) 0.2 + 0.4*k.^2 - 0.1*k + 0.1*sqrt(t);
    taus = [30 60 90 150 240] / 365.25;
    ks = -0.2:0.05:0.2;
    [KK, TT] = meshgrid(ks, taus);
    expiry = "E" + string(round(TT(:) * 365.25));
    res = table(expiry, TT(:), KK(:), ivTrue(KK(:), TT(:)), ...
        'VariableNames', {'expiry', 'tau', 'k', 'iv_matlab'});

    rng(0);
    kq = -0.19 + 0.38 * rand(500, 1);
    tq = taus(1) + 1e-3 + (taus(end) - taus(1) - 2e-3) * rand(500, 1);

    % ---- 1. interpolation accuracy in the interior ------------------------
    sI = build_surface(res, 'Space', 'iv');
    e = abs(sI.F(kq, tq) - ivTrue(kq, tq));
    assert(all(isfinite(e)), 'interior queries must be finite');
    assert(max(e) < 2e-3, 'iv-space interpolation error %.2e', max(e));
    fprintf('[ok] iv-space interpolation: max error %.2e\n', max(e));

    s = build_surface(res);                                  % default: total variance
    e = abs(s.F(kq, tq) - ivTrue(kq, tq));
    assert(max(e) < 1e-2, 'totalvar interpolation error %.2e', max(e));
    fprintf('[ok] total-variance interpolation: max error %.2e\n', max(e));
    assert(s.coverage > 0.9, 'coverage %.2f too low for a full rectangle', s.coverage);

    % ---- 2. no extrapolation ----------------------------------------------
    assert(isnan(s.F(0.5, taus(3))) && isnan(s.F(0, 2.0)), 'outside hull must be NaN');
    fprintf('[ok] queries outside the data hull return NaN\n');

    % Coverage must be a real measure: cut the corners off the data so the hull is
    % smaller than the bounding box, and check the surface shows holes (NaN), never 0s.
    cut = (res.tau == min(res.tau) | res.tau == max(res.tau)) & abs(res.k) > 0.1;
    sC = build_surface(res(~cut, :));
    assert(sC.coverage < 0.99 && sC.coverage > 0.5, 'coverage %.2f should reflect the cut corners', sC.coverage);
    assert(any(isnan(sC.ivGrid(:))) && ~any(sC.ivGrid(:) == 0), 'outside-hull grid cells must be NaN, not 0');
    fprintf('[ok] coverage reflects holes (%.0f%%) and the grid never contains zeros\n', 100 * sC.coverage);

    % ---- 3. slices ----------------------------------------------------------
    sl = smile_slice(s, res, "E90");
    ref = interp1(sl.kMarket, sl.ivMarket, sl.k);
    assert(all(isfinite(sl.iv)) && max(abs(sl.iv - ref)) < 2e-3, 'smile slice mismatch');
    smile_slice(s, res, "E30");                              % boundary expiries must not be NaN
    assert(all(isfinite(smile_slice(s, res, "E30").iv)) && ...
           all(isfinite(smile_slice(s, res, "E240").iv)), 'boundary-expiry smile has NaN');
    ts = term_structure_slice(s, 0);
    assert(numel(ts.iv) > 50 && all(isfinite(ts.iv)), 'term structure slice should be finite');
    assert(all(abs(ts.iv - ivTrue(0, ts.tau)) < 1e-2), 'term structure off from truth');
    fprintf('[ok] smile and term-structure slices (incl. first/last expiry)\n');

    % ---- 4. duplicate points are averaged, not an error ---------------------
    resD = [res; res(5, :)];
    build_surface(resD);
    fprintf('[ok] duplicate (k,tau) rows handled\n');

    % ---- 5. input validation -----------------------------------------------
    expectError(@() build_surface(table(1, 'VariableNames', {'x'})), 'build_surface:missingColumns');
    expectError(@() build_surface(res(res.expiry == "E30", :)), 'build_surface:tooFewPoints');
    expectError(@() smile_slice(s, res, "nope"), 'smile_slice:noExpiry');
    fprintf('[ok] bad inputs rejected with clear errors\n');

    fprintf('\nAll surface checks passed.\n');
end

function expectError(fn, id)
    try
        fn();
    catch err
        assert(strcmp(err.identifier, id), 'expected %s but got %s', id, err.identifier);
        return
    end
    error('test_surface:noError', 'expected error %s but none was thrown', id);
end
