classdef OFDM

    properties
        N,
        L,
        Ndat,
        Npil,
        Nsymb,
        Bw,
        guards,
        pilots,
        data,
        active,
        bandsize,
        left_guard,
        right_guard,
    end

    methods
        function obj = OFDM(options)
            arguments
                options.N = 64
                options.L = 16
                options.Npil = 4
                options.Nsymb = 1
                options.Bw = 0.8
                options.guards = [];
                options.DC_guards = 0;
            end

            obj.N = options.N;
            obj.L = options.L;
            obj.Npil = options.Npil;
            obj.Nsymb = options.Nsymb;
            obj.Bw = options.Bw;

            obj.guards = [options.guards; obj.N/2+1, options.DC_guards];
            obj.left_guard = ceil((1-obj.Bw)*obj.N/2);
            obj.right_guard = floor((1+obj.Bw)*obj.N/2);
            obj.active = obj.left_guard:obj.right_guard;
            obj.active = obj.active.';

            removed_indexes = [];
            for i = 1:size(obj.guards, 1)
                if ismember(obj.guards(i,1), obj.active)
                    a = max(1, obj.guards(i,1)-ceil(obj.guards(i,2)/2)+1);
                    b = min(obj.N, obj.guards(i,1)+floor(obj.guards(i,2)/2));
                    removed_indexes = [removed_indexes, a:b];
                end
            end

            obj.pilots = obj.active(round(linspace(1,length(obj.active),obj.Npil)));
            obj.active = setdiff(obj.active, removed_indexes); 
            obj.data   = setdiff(obj.active, obj.pilots);

            obj.Ndat = length(obj.data);
            obj.bandsize = obj.right_guard-obj.left_guard+1;
        end

        function waveform = mod(obj, data, pilots)
            data = reshape(data, obj.Ndat, []);
            pilots = reshape(pilots, obj.Npil, []);
            buf = complex(zeros(obj.N, obj.Nsymb));
            buf(obj.data,:) = data;
            buf(obj.pilots,:) = pilots;

            buf = ifft(fftshift(buf), obj.N);
            buf = [buf(end-obj.L+1:end, :);buf];
            waveform = buf(:);
        end   

        function [band, data, pilots] = demod(obj, waveform)
            waveform = waveform(1:obj.Nsymb*(obj.N+obj.L));
            waveform = reshape(waveform, obj.N+obj.L, []);
            waveform = waveform(obj.L+1:end,:);
            waveform = fftshift(fft(waveform, obj.N));

            band = waveform(obj.left_guard:obj.right_guard,:);
            data   = waveform(obj.data, :);
            pilots = waveform(obj.pilots, :);
        end
    end
end
