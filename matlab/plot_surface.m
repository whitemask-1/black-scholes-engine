function plot_surface(s, res, ax)
%PLOT_SURFACE 3-D implied vol surface with the market points overlaid.
%   plot_surface(s, res)        new figure
%   plot_surface(s, res, ax)    draw into an existing axes (e.g. an App Designer UIAxes)
%   Maturity is shown in days; holes are regions outside the data hull.
    if nargin < 3 || isempty(ax)
        figure('Color', 'w');  ax = axes;
    end
    surf(ax, s.kGrid, s.tauGrid * 365.25, s.ivGrid, 'EdgeAlpha', 0.25);
    hold(ax, 'on');
    scatter3(ax, res.k, res.tau * 365.25, res.iv_matlab, 18, 'k', 'filled');
    hold(ax, 'off');
    xlabel(ax, 'log-moneyness  ln(K/F)');
    ylabel(ax, 'days to expiry');
    zlabel(ax, 'implied volatility');
    title(ax, sprintf('Implied volatility surface (%s, %s)', s.method, s.space));
    colorbar(ax);  view(ax, [-40 28]);  grid(ax, 'on');
end
