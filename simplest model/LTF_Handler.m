classdef LTF_Handler < handle
    
    properties
        ltf
        sto
        sfo
        h
        H
        eqv
        h_window
        debug
    end

    methods
        function obj = LTF_Handler(ltf, options)
            arguments
                ltf 
                options.h_window = ltf.L;
                options.sto_shift = -ltf.L/2;
                options.debug = false;
            end

            obj.ltf = ltf;
            obj.sto = 0;
            obj.sfo = 0;
            obj.h = [];
            obj.H = [];
            obj.eqv = [];
            obj.h_window = options.h_window;
            obj.debug = options.debug;
        end

        function sto = find_sto(obj, waveform)
            buf = waveform(1:2*obj.ltf.N);
            obj.H = fft(buf)./fft(obj.ltf.ref);
            obj.h = ifft(obj.H);

            [max_val, max_index] = max(abs(obj.h));
            
            obj.sto = max_index+length(obj.ltf.waveform)+obj.ltf.sto_shift;
            sto = obj.sto;
        end

        function est = estimate(obj, waveform, options)
            arguments
                obj 
                waveform 
                options.sfo = 0
                options.beta = 0.1
            end
            
            buf = waveform(1:2*obj.ltf.N);
            obj.H = fft(buf)./fft(obj.ltf.ref);
            obj.h = ifft(obj.H);

            [max_val, max_index] = max(abs(obj.h));

            if obj.debug
                fprintf("Start  estimation\n");

                figure(200);
                clf;

                subplot(2,1,1)
                plot(real(buf));
                hold("on");

                plot(abs(obj.h));

                subplot(2,1,2);
                plot(abs(obj.h));

                fprintf("Max val: %f index %d\n", max_val, max_index);
            end

            obj.sto = max_index+length(obj.ltf.waveform)+obj.ltf.sto_shift;

            buf = waveform(max_index+2*obj.ltf.N:max_index+(obj.ltf.Nsymb-2)*obj.ltf.N-1);
            buf = reshape(buf, [], obj.ltf.Nsymb/2-2);

            obj.H = fft(buf)./fft(obj.ltf.ref);
            options.sfo = options.sfo*(2*obj.ltf.N)/(obj.ltf.L+obj.ltf.N);
            t = options.sfo*(1:2*obj.ltf.N)';

            for i = 2:obj.ltf.Nsymb/2-2
                obj.H(:, i) = options.beta*obj.H(:, i) + (1-options.beta)*obj.H(:, i-1); %.*exp(-1i*t);
            end
            obj.H = obj.H(:,end);

            % buf = mean(buf,2);

            % obj.H = fft(buf)./fft(obj.ltf.ref);
            obj.h = ifft(obj.H);

            [max_val, ~] = max(abs(obj.h));
            
            obj.h(obj.h_window/2+1:end-obj.h_window) = 0;

            obj.h = circshift(obj.h, -obj.ltf.sto_shift);
            obj.H = fft(obj.h);
            obj.H = obj.H(1:2:end);


            if obj.debug
                figure(201);

                subplot(3,1,1);
                plot(abs(obj.h));

                subplot(3,1,2);
                val = abs(fftshift(obj.H));
                val = (val/max(val));
                plot(val);
                ylim([0, 1]);

                subplot(3,1,3);
                val = unwrap(angle(fftshift(obj.H)));
                plot(val);
            end
                      
            obj.eqv = conj(obj.H)./(abs(obj.H.^2)+1e-6);
            % obj.eqv = 1.0./(obj.H+1e-6*exp(1i*pi*angle(obj.H)));

            est = true;
        end

    end
end