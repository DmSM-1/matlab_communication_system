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

        ofdmMod
        ofdmDemod

        data
        mod_data
        waveform
        
        eqv

        debug

        eqv_pilotIdx

        alpha
        beta

    end

    methods
        function obj = DATA_Handler(options)
            arguments
                options.N = 64;
                options.L = 16;
                options.Ndat = 48;
                options.Npil = 2;

                options.Mod_pow = 1;
                options.Nsymb = 1;
                options.Cod_rate = 1;
                options.alpha = 0.1;
                options.beta = 0.1;

                options.debug = false;
            end

            obj.N = options.N;
            obj.L = options.L;
            obj.Ndat = options.Ndat;
            obj.Npil = options.Npil;

            obj.Mod_pow = options.Mod_pow;
            obj.Nsymb = options.Nsymb;
            obj.Cod_rate = options.Cod_rate;

            obj.NumGuardBandCarriers = (obj.N-obj.Ndat-obj.Npil-1);

            obj.ofdmMod = comm.OFDMModulator( ...
                'FFTLength', obj.N, ...
                'NumGuardBandCarriers', [floor(obj.NumGuardBandCarriers/2);ceil(obj.NumGuardBandCarriers/2)], ...
                'InsertDCNull', true, ...
                'CyclicPrefixLength', obj.L, ...
                'Windowing', false, ...
                'OversamplingFactor', 1, ...
                'NumSymbols', 1, ...
                'NumTransmitAntennas', 1, ...
                'PilotInputPort', true ...
                );

            obj.ofdmDemod = comm.OFDMDemodulator( ...
                'FFTLength', obj.N, ...
                'NumGuardBandCarriers', [floor(obj.NumGuardBandCarriers/2);ceil(obj.NumGuardBandCarriers/2)], ...
                'RemoveDCCarrier', true, ...
                'CyclicPrefixLength', obj.L, ...
                'OversamplingFactor', 1, ...
                'NumSymbols', 1, ...
                'NumReceiveAntennas', 1, ...
                'PilotOutputPort', false ...
                );

            obj.left_guard = floor(obj.NumGuardBandCarriers/2);
            obj.right_guard   = obj.N-ceil(obj.NumGuardBandCarriers/2);
            pilot_dist  = floor((obj.N-obj.NumGuardBandCarriers-1)/(obj.Npil-1));
            
            obj.pilotIdx = obj.left_guard+1:pilot_dist:obj.right_guard;
            obj.pilotIdx(floor(obj.Npil/2)+1:end) = obj.pilotIdx(floor(obj.Npil/2)+1:end)+mod(obj.Ndat+obj.Npil, pilot_dist);
            obj.ofdmMod.PilotCarrierIndices = obj.pilotIdx.';
            obj.payload = floor(obj.Nsymb*obj.Ndat*obj.Cod_rate*obj.Mod_pow*obj.Cod_rate);

            obj.data = [];
            obj.mod_data = [];
            obj.waveform = [];

            obj.eqv = complex(ones(obj.N, 1));

            obj.debug = options.debug;

            obj.eqv_pilotIdx = obj.pilotIdx-obj.left_guard;
            obj.eqv_pilotIdx(obj.Npil/2+1:end) = obj.eqv_pilotIdx(obj.Npil/2+1:end) - 1;
            obj.alpha = options.alpha;
            obj.beta = options.beta;

        end

        function waveform = get_waveform(obj, data)
            obj.data = reshape(data, [], 1);

            obj.Nsymb = int32(length(data)/(obj.Ndat*obj.Mod_pow*obj.Cod_rate));
            obj.payload = floor(obj.Nsymb*obj.Ndat*obj.Cod_rate*obj.Mod_pow*obj.Cod_rate);

            pilots = pskmod(zeros(obj.Npil, obj.Nsymb), 2);
            obj.mod_data = qammod(obj.data, 2^obj.Mod_pow, 'gray', 'InputType', 'bit', 'UnitAveragePower', true);
            obj.mod_data = reshape(obj.mod_data, obj.Ndat, []);

            obj.waveform = complex(zeros(obj.N+obj.L, obj.Nsymb));

            for i = 1:obj.Nsymb
                obj.waveform(:, i) = obj.ofdmMod(obj.mod_data(:, i), pilots(:, i));
            end

            obj.waveform = obj.waveform(:);
            
            obj.waveform = obj.waveform./sqrt((mean(abs(obj.waveform.^2))));
            waveform = obj.waveform;
        end

        function eqv = set_eqv(obj, ltf_handler)
            obj.eqv = ltf_handler.eqv;
            obj.eqv = [obj.eqv(obj.N/2+1+floor(obj.NumGuardBandCarriers/2):end);...
                       obj.eqv(2:obj.N/2-ceil(obj.NumGuardBandCarriers/2))];
            eqv = obj.eqv;
        end

        function [ifft_data, rx_res_data, rx_eqv_data, rx_eqv_pilots] = get_data(obj, waveform)

            waveform = reshape(waveform, [], obj.Nsymb);
            ifft_data = complex(zeros(obj.Ndat+obj.Npil, obj.Nsymb));

            for i = 1:obj.Nsymb
                ifft_data(:, i) = obj.ofdmDemod(waveform(:, i)); 
            end

            rx_eqv_data = zeros(size(ifft_data));
            indices = (1:obj.Ndat+obj.Npil).';


            for i = 1:obj.Nsymb
                rx_eqv_data(:, i) = ifft_data(:, i).*obj.eqv;

                pilot_eqv = rx_eqv_data(obj.eqv_pilotIdx, i);
                pilot_eqv = interp1(obj.eqv_pilotIdx, pilot_eqv, indices, 'linear', 'extrap');
                pilot_eqv = (1-obj.alpha)*ones(size(pilot_eqv))+obj.alpha*pilot_eqv;
                pilot_eqv = 1.0./(pilot_eqv+1e-6*exp(1i*pi*angle(pilot_eqv)));

                rx_eqv_data(:, i) = rx_eqv_data(:, i).*pilot_eqv;
                rx_eqv_pilots = rx_eqv_data(obj.eqv_pilotIdx, i);
                rx_eqv_data(:, i) = rx_eqv_data(:, i)./sqrt(mean(abs(rx_eqv_pilots.^2)));
                
                rx_res_data = rx_eqv_data(:, i);
                rx_res_data(obj.eqv_pilotIdx, :) = [];
                rx_res_data = qamdemod(rx_res_data, 2^obj.Mod_pow, 'gray', 'OutputType', 'bit', 'UnitAveragePower', true);
                rx_res_data = reshape(rx_res_data, [], 1);
                
                pilots = pskmod(zeros(obj.Npil, 1), 2);
                rx_res_data = qammod(rx_res_data, 2^obj.Mod_pow, 'gray', 'InputType', 'bit', 'UnitAveragePower', true);
                
                new_H = ifft_data(:, i)./obj.ofdmDemod(obj.ofdmMod(rx_res_data, pilots));
                new_eqv = 1.0./(new_H+1e-1*exp(1i*pi*angle(new_H)));
                obj.eqv = obj.eqv + obj.beta*(new_eqv-obj.eqv);

            end

            rx_eqv_pilots = rx_eqv_data(obj.eqv_pilotIdx, :);
            rx_eqv_data(obj.eqv_pilotIdx, :) = [];
            rx_res_data = qamdemod(rx_eqv_data, 2^obj.Mod_pow, 'gray', 'OutputType', 'bit', 'UnitAveragePower', true);
            rx_res_data = reshape(rx_res_data, [], 1);

            % if obj.debug
            %     ber = mean(xor(rx_res_data,obj.data));
            %     mod_mse = sqrt(mean(abs(rx_eqv_data(:)-obj.mod_data(:)).^2));
            %     fprintf("BER:  %f\nRMSE: %f\n", ber, mod_mse);
            % 
            %     ifft_data = ifft_data./sqrt(mean(abs(ifft_data.^2)));
            % 
            %     % figure(1);
            %     % clf;
            %     nexttile;
            %     scatter(real(ifft_data(:)), imag(ifft_data(:)), 3, 'blue', c='.');
            %     hold("on");
            %     scatter(real(rx_eqv_data(:).'), imag(rx_eqv_data(:).'), 3, 'red', c='.');
            %     hold("on");
            %     scatter(real(rx_eqv_pilots(:).'), imag(rx_eqv_pilots(:).'), 7, 'green', c='.');
            % 
            %     xlim([-2, 2]);
            %     ylim([-2, 2]);
            %     axis("square");
            % 
            % end
        end    

    end
end