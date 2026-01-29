classdef DATA_Handler < handle

    properties
        N
        L
        Ndat
        Npil

        Mod_pow
        Nsymb
        Cod_rate

        NumGuardBandCarriers
        left_guard
        right_guard
        pilotIdx
        payload

        ofdm
        ofdmMod
        ofdmDemod

        data
        mod_data
        waveform
        ang
        
        eqv

        debug

        eqv_pilotIdx
        dataIdx
        activeIdx

        alpha
        beta

        crcCfg

    end

    methods
        function obj = DATA_Handler(options)
            arguments
                options.N = 64;
                options.L = 16;
                options.Ndat = 48;
                options.Npil = 2;
                options.Bw = 0.5;

                options.Mod_pow = 1;
                options.Nsymb = 1;
                options.Cod_rate = 1;
                options.alpha = 0.1;
                options.beta = 0.1;
                options.guards = [];
                options.DC_guard = 1;

                options.debug = false;
            end

            obj.N = options.N;
            obj.L = options.L;
            obj.Npil = options.Npil;
            obj.Nsymb = options.Nsymb;
            
            obj.ofdm = OFDM( ...
                N=obj.N, ...
                L=obj.L, ...
                Npil=obj.Npil, ...
                Bw=options.Bw, ...
                guards=options.guards, ...
                DC_guards=options.DC_guard ...
            );

            obj.Ndat = obj.ofdm.Ndat;
            obj.Mod_pow = options.Mod_pow;
            obj.Cod_rate = options.Cod_rate;

            obj.payload = obj.Nsymb*(floor(obj.Ndat*obj.Cod_rate*obj.Mod_pow)-32);

            obj.data = [];
            obj.mod_data = [];
            obj.waveform = [];
            obj.ang = zeros(obj.Nsymb, 1);

            obj.eqv = complex(ones(obj.N, 1));

            obj.debug = options.debug;

            obj.eqv_pilotIdx = obj.ofdm.pilots-obj.ofdm.left_guard+1;
            obj.dataIdx = obj.ofdm.data-obj.ofdm.left_guard+1;
            obj.activeIdx = obj.ofdm.active-obj.ofdm.left_guard+1;
            obj.alpha = options.alpha;
            obj.beta = options.beta;

            poly = 'z^32 + z^26 + z^23 + z^22 + z^16 + z^12 + z^11 + z^10 + z^8 + z^7 + z^5 + z^4 + z^2 + z + 1';
            obj.crcCfg = crcConfig(Polynomial=poly,ChecksumsPerFrame=1);

        end

        function data = generate_data(obj, options)
            arguments
                obj 
                options.source_data = [] 
            end
            
            BPS = obj.payload/obj.Nsymb;

            if isempty(options.source_data)
                options.source_data = randi([0, 1], BPS, obj.Nsymb);
            else
                options.source_data = reshape(options.source_data, BPS, obj.Nsymb);
            end

            source_bits = zeros(BPS+32, obj.Nsymb);
            for i = 1:obj.Nsymb
                source_bits(:,i) = crcGenerate(options.source_data(:,i), obj.crcCfg);
            end
            data = source_bits(:);
        end

        function waveform = get_waveform(obj, data)
            obj.data = reshape(data, [], 1);

            obj.Nsymb = int32(length(data)/(obj.Ndat*obj.Mod_pow*obj.Cod_rate));
            obj.payload = floor(obj.Nsymb*obj.Ndat*obj.Cod_rate*obj.Mod_pow);

            pilots = pskmod(zeros(obj.Npil, obj.Nsymb), 2);
            obj.mod_data = qammod(obj.data, 2^obj.Mod_pow, 'gray', 'InputType', 'bit', 'UnitAveragePower', true);
            obj.mod_data = reshape(obj.mod_data, obj.Ndat, []);

            obj.waveform = complex(zeros(obj.N+obj.L, obj.Nsymb));

            for i = 1:obj.Nsymb
                obj.waveform(:, i) = obj.ofdm.mod(obj.mod_data(:, i), pilots(:, i));
            end

            obj.waveform = obj.waveform(:);
            
            obj.waveform = obj.waveform./sqrt((mean(abs(obj.waveform.^2))));
            waveform = obj.waveform;
        end

        function eqv = set_eqv(obj, ltf_handler)
            obj.eqv = ltf_handler.eqv;
            obj.eqv = fftshift(obj.eqv);
            obj.eqv = obj.eqv(obj.ofdm.left_guard:obj.ofdm.right_guard);

            eqv = obj.eqv;
        end

        function [mod_data, rx_res_data, rx_eqv_data, rx_eqv_pilots] = get_data(obj, waveform, options)
            arguments
                obj 
                waveform 
                options.crc = false 
                options.ideal = false
                options.source = []
            end
            mod_data = complex(zeros(obj.ofdm.bandsize, obj.Nsymb));
            ifft_data = complex(zeros(obj.ofdm.bandsize, obj.Nsymb));
            pilots = complex(zeros(obj.Npil, obj.Nsymb));
            rx_eqv_data = zeros(size(ifft_data));
            indices = (1:obj.ofdm.bandsize).';

            if ~isempty(options.source)
                options.source = reshape(options.source, [], obj.Nsymb);
            end

            iter = 0;
            
            for i = 1:obj.Nsymb
                [mod_data(:, i), ~, pilots(:, i)] = obj.ofdm.demod(waveform(iter+1:iter+(obj.N+obj.L)));
                iter = iter+(obj.N+obj.L);
            end

            pilots = unwrap(angle(pilots.'));

            sfo = median(diff(pilots(:,obj.Npil)-pilots(:,1)));
            sfo = sfo/(obj.ofdm.pilots(obj.Npil)-obj.ofdm.pilots(1));

            pilots = mean(pilots, 2);
            obj.ang(:,1) = pilots;

            x = double(1:obj.Nsymb);
            p = polyfit(x, pilots, 1);
            dp = p(1)/(obj.L+obj.N);
            phase = 0;
            for i = 1:length(waveform)
                phase = phase + dp;
                waveform(i) = waveform(i)*exp(-1i*phase);
            end
            
            iter = 0;
            t = 1:length(obj.eqv);
            t = t.';
            t = t-length(obj.eqv)/2;
            
            for i = 1:obj.Nsymb
                [ifft_data(:, i), ~, ~] = obj.ofdm.demod(waveform(iter+1:iter+(obj.N+obj.L)));
                iter = iter+obj.N+obj.L;

                rx_eqv_data(:, i) = ifft_data(:, i).*obj.eqv;
                
                pilot_eqv = rx_eqv_data(obj.eqv_pilotIdx, i);
                pilot_eqv = interp1(obj.eqv_pilotIdx, pilot_eqv, indices, 'linear', 'extrap');
                pilot_eqv = (1-obj.alpha)*ones(size(pilot_eqv))+obj.alpha*pilot_eqv;
                pilot_eqv = conj(pilot_eqv)./(abs(pilot_eqv.^2)+1e-3);
                
                rx_eqv_data(:, i) = rx_eqv_data(:, i).*pilot_eqv;
                rx_eqv_pilots = rx_eqv_data(obj.eqv_pilotIdx, i);
                rx_eqv_data(:, i) = rx_eqv_data(:, i)./sqrt(mean(abs(rx_eqv_pilots.^2)));
                

                if ~isempty(options.source);
                    pilots = pskmod(zeros(obj.Npil, 1), 2);
                    rx_mod_res_data = qammod(options.source(:,i), 2^obj.Mod_pow, 'gray', 'InputType', 'bit', 'UnitAveragePower', true);
                
                    [rx_demod_res_data, ~, ~] = obj.ofdm.demod(obj.ofdm.mod(rx_mod_res_data, pilots));

                    new_H = ifft_data(:, i)./rx_demod_res_data;
                
                    new_eqv = conj(new_H)./(abs(new_H.^2)+1e-3);
                    obj.eqv = obj.eqv + obj.beta*(new_eqv-obj.eqv);

                    val = polyfit(obj.eqv_pilotIdx, angle(conj(obj.eqv(obj.eqv_pilotIdx))), 1);
                    obj.ang(i,1) = val(2);
                    continue
                end


                rx_res_data = rx_eqv_data(obj.dataIdx, i);
                rx_res_bin_data = qamdemod(rx_res_data, 2^obj.Mod_pow, 'gray', 'OutputType', 'bit', 'UnitAveragePower', true);
                rx_res_bin_data = reshape(rx_res_bin_data, [], 1);
                
                [~,err] = crcDetect(rx_res_bin_data,obj.crcCfg);
                
                if ~(err&&options.crc)
                    pilots = pskmod(zeros(obj.Npil, 1), 2);
                    rx_mod_res_data = qammod(rx_res_bin_data, 2^obj.Mod_pow, 'gray', 'InputType', 'bit', 'UnitAveragePower', true);
                    
                    [rx_demod_res_data, ~, ~] = obj.ofdm.demod(obj.ofdm.mod(rx_mod_res_data, pilots));
    
                    new_H = ifft_data(:, i)./rx_demod_res_data;
                    
                    new_eqv = conj(new_H)./(abs(new_H.^2)+1e-3);
                    obj.eqv = obj.eqv + obj.beta*(new_eqv-obj.eqv);
                else
                    obj.eqv = obj.eqv.*exp(-1i*sfo*t);
                end

            end

            rx_eqv_pilots   = rx_eqv_data(obj.eqv_pilotIdx, :);
            rx_eqv_data     = rx_eqv_data(obj.dataIdx, :);
            
            rx_res_data     = qamdemod(rx_eqv_data, 2^obj.Mod_pow, 'gray', 'OutputType', 'bit', 'UnitAveragePower', true);
            rx_res_data     = reshape(rx_res_data, [], 1);

        end

    end
end