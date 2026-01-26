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

        function est = estimate(obj, waveform)
            arguments
                obj 
                waveform 
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

            obj.sto = max_index+length(obj.ltf.waveform);

            buf = waveform(max_index:max_index+2*obj.ltf.N-1);
            obj.H = fft(buf)./fft(obj.ltf.ref);
            obj.h = ifft(obj.H);

            [max_val, ~] = max(abs(obj.h));
            
            obj.h(obj.h_window/2+1:end-obj.h_window) = 0;
            obj.H = fft(obj.h);
            obj.H = obj.H(1:2:end);
            
            %sfo estimation
            % buf = waveform(max_index:max_index+obj.ltf.Nsymb*obj.ltf.N-1);
            % buf = reshape(buf, 2*obj.ltf.N, []);
            % buf = fft(buf)./fft(obj.ltf.ref);
            % buf = fftshift(buf);
            % buf = unwrap(angle(buf));
            % 
            % x = 1:2*obj.ltf.N;
            % x = x.';
            % 
            % a = zeros(obj.ltf.Nsymb/2,1);
            % for i = 1:obj.ltf.Nsymb/2
            %     b = polyfit(x, buf(:,i), 1);
            %     a(i,1) = b(1);
            % end
            % 
            % figure(7);
            % plot(buf);

            
            

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
                      
            obj.eqv = 1.0./(obj.H+1e-1*exp(1i*pi*angle(obj.H)));

            
            est = true;
        end

    end
end