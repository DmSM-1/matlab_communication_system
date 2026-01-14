classdef STF

   % Structure ============================================================
   % Detect | GC | margin1 | CFO&Noise est | margin2 |
   %=======================================================================

    properties
        N
        L
        symb_len
        Ppos        % pilot's position
        Nsymb       % num symbols
        margin1     
        est_symb
        margin2
        waveform    % preamble
        det_mask
        det_threshold
        period 
    end

    methods
        function obj = STF(N,L, options)
            arguments
                N
                L
                options.Ppos = [0.25 ,0.75]*N+1;
                options.margin1 = 0
                options.est_symb = 1
                options.margin2 = 0
                options.det_mask_width = 5
                options.det_threshold = 1.0
            end

            obj.N = N;
            obj.L = L;
            obj.symb_len = N+L;
            obj.Ppos = int32(round(options.Ppos));
            obj.Nsymb = 1+1+options.margin1+options.est_symb+options.margin2;
            obj.margin1 = options.margin1;
            obj.est_symb = options.est_symb;
            obj.margin2 = options.margin2;
            obj.period = obj.L;
            
            waveform = complex(zeros(N, obj.Nsymb));
            
            ampl = N/sqrt(length(options.Ppos));

            for i = 1:obj.Nsymb
                waveform(obj.Ppos, i) = ampl*exp(2i*pi*(i-1)*(L/N)*double(obj.Ppos-1));
            end
            
            waveform = ifft(waveform, N, 1);
            waveform = vertcat(waveform(end-obj.L+1:end, :), waveform);

            obj.waveform = waveform(:);

            det_mask = zeros(N, 1);
            det_mask(obj.Ppos) = 1;
            det_mask = conv(det_mask, ones(options.det_mask_width,1), "same");

            obj.det_mask = det_mask;
            obj.det_threshold = options.det_threshold;
            
            g = obj.Ppos(1)-1;
            
            for i = obj.Ppos
                g = gcd(g, i-1);
            end

            if mod(N, g) ~= 0
                error('STF:InvalidPeriod', 'STF:InvalidPeriod');
            end

            obj.period = int32(N/g);

        end
    end
end