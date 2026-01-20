classdef OFDM_System < handle

    properties
        % Внутренние модули
        chan
        stf
        ltf
        data_handler
        
        % Конфигурация и пути
        Config
        OutputDir % Путь к папке результатов
    end

    methods
        function obj = OFDM_System(options)
            arguments
                % --- System / Path Parameters ---
                options.OutputDir (1,1) string = "Results/Experiment_01" % Путь по умолчанию
                
                % --- Global Parameters ---
                options.N (1,1) double = 1024
                options.L (1,1) double = 32
                options.Fs (1,1) double = 20e6
                
                % --- Channel Parameters ---
                options.ChanModel char = 'Model-B'
                options.dist (1,1) double = 10
                options.Fc (1,1) double = 2.4e9
                options.SNR (1,1) double = 100
                options.CFO (1,1) double = 1000
                options.max_random_sto (1,1) double = 10000
                
                % --- STF Parameters ---
                options.stf_Ppos = [] 
                options.stf_margin1 (1,1) double = 1
                options.stf_est_symb (1,1) double = 4
                options.stf_margin2 (1,1) double = 1
                options.stf_mask_width (1,1) double = 5
                options.stf_threshold (1,1) double = 10.0
                
                % --- LTF Parameters ---
                options.ltf_Nsymb (1,1) double = 8
                
                % --- Data Parameters ---
                options.Ndat (1,1) double = 512
                options.Npil (1,1) double = 8
                options.data_Nsymb (1,1) double = 2000
                options.Mod_pow (1,1) double = 4
                options.Cod_rate (1,1) double = 1
                options.alpha (1,1) double = 0.5
                options.beta (1,1) double = 0.5
                options.debug (1,1) logical = true
            end
            
            % 1. Управление директорией (Overwrite / Create)
            obj.OutputDir = options.OutputDir;
            
            if ~exist(obj.OutputDir, 'dir')
                % Если папки нет - создаем
                mkdir(obj.OutputDir);
            end
            
            
            % 2. Обработка параметров
            if isempty(options.stf_Ppos)
                options.stf_Ppos = [0.25, 0.75] * options.N + 1;
            end
            
            obj.Config = options;

            % 3. Сохранение конфигурации
            % Сохраняем структуру options в файл config.mat внутри папки
            configPath = fullfile(obj.OutputDir, 'config.mat');
            save(configPath, 'options');
            
            % Опционально: можно сохранить в JSON для читаемости человеком
            % jsonText = jsonencode(options, 'PrettyPrint', true);
            % fid = fopen(fullfile(obj.OutputDir, 'config.json'), 'w');
            % fprintf(fid, '%s', jsonText);
            % fclose(fid);


            % 4. Инициализация подсистем
            obj.chan = Channel( ...
                Model = options.ChanModel, ...
                dist  = options.dist, ...
                Fc    = options.Fc, ...
                Fs    = options.Fs, ...
                SNR   = options.SNR, ...
                CFO   = options.CFO, ...
                max_random_sto = options.max_random_sto ...
            );

            obj.stf = STF( ...
                options.N, options.L, ...
                Ppos           = options.stf_Ppos, ...
                margin1        = options.stf_margin1, ...
                est_symb       = options.stf_est_symb, ...
                margin2        = options.stf_margin2, ...
                det_mask_width = options.stf_mask_width, ...
                det_threshold  = options.stf_threshold ...
            );

            obj.ltf = LTF( ...
                options.N, options.L, ...
                Nsymb = options.ltf_Nsymb ...
            );

            obj.data_handler = DATA_Handler( ...
                N        = options.N, ...
                L        = options.L, ...
                Ndat     = options.Ndat, ...
                Npil     = options.Npil, ...
                Nsymb    = options.data_Nsymb, ...
                Mod_pow  = options.Mod_pow, ...
                Cod_rate = options.Cod_rate, ...
                alpha    = options.alpha, ...
                beta     = options.beta, ...
                debug    = options.debug ...
            );
            
            % Если нужно сохранить ВЕСЬ объект после инициализации:
            % save(fullfile(obj.OutputDir, 'system_obj.mat'), 'obj');
        end

        function [tx_waveform, source_bits] = generate_frame(obj, seed)
            arguments
                obj
                seed = [] 
            end

            % --- 1. Генерация данных ---
            if ~isempty(seed)
                rng(seed);
            end

            num_bits = obj.data_handler.payload;
            source_bits = randi([0, 1], num_bits, 1);
            
            % Генерируем waveform (внутри data_handler обновляется поле mod_data)
            data_wav = obj.data_handler.get_waveform(source_bits);
            
            % ИЗВЛЕКАЕМ МОДУЛИРОВАННЫЕ СИМВОЛЫ (QAM)
            % Это нужно для расчета EVM/RMSE без повторной модуляции
            tx_mod_symbols = obj.data_handler.mod_data;
            
            % Сборка полного кадра
            tx_waveform = [obj.stf.waveform; obj.ltf.waveform; data_wav];

            % --- 2. Логика файловой системы ---
            
            % Получаем список всех папок внутри OutputDir
            files = dir(obj.OutputDir);
            dirFlags = [files.isdir];
            subDirs = files(dirFlags);
            folderNames = {subDirs.name};
            
            % Фильтрация имен
            folderNames = folderNames(~ismember(folderNames, {'.', '..'}));
            folderNums = str2double(folderNames);
            validNums = folderNums(~isnan(folderNums));
            
            % Определение следующего индекса
            if isempty(validNums)
                nextIdx = 1;
            else
                nextIdx = max(validNums) + 1;
            end
            
            % --- 3. Создание папки и сохранение ---
            
            newDirName = num2str(nextIdx);
            currentSaveDir = fullfile(obj.OutputDir, newDirName);
            
            mkdir(currentSaveDir);
            
            savePath = fullfile(currentSaveDir, 'tx_data.mat');
            
            % СОХРАНЯЕМ 3 ПЕРЕМЕННЫЕ: волну, биты и QAM-символы
            save(savePath, 'tx_waveform', 'source_bits', 'tx_mod_symbols');
        end
        
        function run_channel_on_dataset(obj)
            % RUN_CHANNEL_ON_DATASET Сканирует папку OutputDir, находит все
            % подпапки с номерами (1, 2...), загружает оттуда tx_waveform,
            % прогоняет через текущий канал и сохраняет rx_waveform.

            fprintf('--- Start Channel Simulation on Dataset ---\n');
            fprintf('Target Directory: %s\n', obj.OutputDir);

            % 1. Сканируем папку на наличие числовых подпапок
            files = dir(obj.OutputDir);
            dirFlags = [files.isdir];
            subDirs = files(dirFlags);
            folderNames = {subDirs.name};
            
            % Убираем '.' и '..'
            folderNames = folderNames(~ismember(folderNames, {'.', '..'}));
            
            % Преобразуем в числа
            folderNums = str2double(folderNames);
            validNums = folderNums(~isnan(folderNums));
            
            % Сортируем, чтобы обрабатывать по порядку (1, 2, 3...)
            validNums = sort(validNums);

            if isempty(validNums)
                warning('No numbered folders found in directory!');
                return;
            end

            totalFolders = length(validNums);
            fprintf('Found %d folders. Processing...\n', totalFolders);

            % 2. Цикл по всем найденным папкам
            % Используем reverseStr для красивой анимации прогресса в консоли
            reverseStr = ''; 

            for i = 1:totalFolders
                folderIdx = validNums(i);
                
                % Формируем пути
                currentDir = fullfile(obj.OutputDir, num2str(folderIdx));
                txFile = fullfile(currentDir, 'tx_data.mat');
                rxFile = fullfile(currentDir, 'rx_data.mat');
                
                % Проверяем наличие файла с данными передачи
                if exist(txFile, 'file')
                    % Загружаем tx_waveform
                    % load возвращает структуру, берем поле оттуда
                    loadedData = load(txFile, 'tx_waveform');
                    
                    if isfield(loadedData, 'tx_waveform')
                        % --- ПРОГОН ЧЕРЕЗ КАНАЛ ---
                        rx_waveform = obj.chan.tx(loadedData.tx_waveform);
                        
                        % --- СОХРАНЕНИЕ ---
                        save(rxFile, 'rx_waveform');
                    else
                        fprintf('\nWarning: Folder %d does not contain tx_waveform variable.\n', folderIdx);
                    end
                else
                    fprintf('\nWarning: tx_data.mat not found in folder %d.\n', folderIdx);
                end
                
                % Вывод прогресса
                msg = sprintf('Processed: %d / %d (Folder ID: %d)', i, totalFolders, folderIdx);
                fprintf([reverseStr, msg]);
                reverseStr = repmat('\b', 1, length(msg));
            end
            
            fprintf('\n--- Done ---\n');
        end

        function generate_dataset(obj, num_frames)
            arguments
                obj
                num_frames (1,1) double {mustBePositive, mustBeInteger}
            end

            % Удаляем только папки с именами "1", "2", "100" и т.д.
            
            files = dir(obj.OutputDir);
            dirFlags = [files.isdir]; % Берем только папки
            subDirs = files(dirFlags);
            folderNames = {subDirs.name};
            
            % Исключаем служебные '.' и '..'
            folderNames = folderNames(~ismember(folderNames, {'.', '..'}));
            
            % Проверяем, является ли имя числом
            folderNums = str2double(folderNames);
            isNumberedFolder = ~isnan(folderNums); % Маска: true, если имя - число
            
            foldersToDelete = folderNames(isNumberedFolder);
            
            if ~isempty(foldersToDelete)
                fprintf('Cleaning up %d old data folders...\n', length(foldersToDelete));
                for k = 1:length(foldersToDelete)
                    folderPath = fullfile(obj.OutputDir, foldersToDelete{k});
                    rmdir(folderPath, 's'); % 's' удаляет папку вместе с содержимым
                end
            else
                fprintf('Directory is clean. No numbered folders found.\n');
            end

            fprintf('--- Start Data Generation ---\n');
            fprintf('Target Directory: %s\n', obj.OutputDir);
            
            reverseStr = ''; 
            t_start = tic;

            for i = 1:num_frames
                % Формируем сообщение прогресса
                msg = sprintf('Generating: %3d / %d', i, num_frames);
                
                % Печатаем (удаляя предыдущее сообщение)
                fprintf([reverseStr, msg]);
                
                % Вызываем генерацию одного кадра
                % Передаем 'i' в качестве seed, чтобы кадры были разными,
                % но воспроизводимыми
                obj.generate_frame(i);
                
                % Готовим строку удаления для следующего шага
                reverseStr = repmat('\b', 1, length(msg));
            end
            
            t_total = toc(t_start);
            fprintf('\nDone! Total time: %.2f s\n', t_total);
        end


        function process_dataset(obj)
            % PROCESS_DATASET Загружает сохраненные rx_waveform из папок,
            % прогоняет через приемник (STF->LTF->Data) и считает ошибки.

            fprintf('--- Start Processing Dataset (Rx Analysis) ---\n');
            fprintf('Directory: %s\n', obj.OutputDir);

            % 1. Сканируем папки
            files = dir(obj.OutputDir);
            subDirs = files([files.isdir]);
            folderNames = {subDirs.name};
            folderNames = folderNames(~ismember(folderNames, {'.', '..'}));
            folderNums = str2double(folderNames);
            validNums = sort(folderNums(~isnan(folderNums)));

            if isempty(validNums)
                warning('No data folders found!');
                return;
            end
            
            totalFrames = length(validNums);
            
            % 2. Инициализация Хендлеров (используем конфиги из self)
            % Создаем локальные экземпляры для обработки
            stf_h = STF_Handler(obj.stf, debug=false);
            ltf_h = LTF_Handler(obj.ltf, h_window=4*obj.Config.L, debug=false);
            
            % DATA_Handler уже является частью obj, используем его
            
            % Заголовок таблицы
            fprintf('| %4s | %8s | %8s | %8s | %s |\n', 'ID', 'BER', 'RMSE', 'CFO', 'Status');
            fprintf('|%s|\n', repmat('-', 1, 46));

            total_ber = 0;
            total_rmse = 0;
            valid_count = 0;

            % 3. Цикл по датасету
            for i = 1:totalFrames
                folderIdx = validNums(i);
                currentDir = fullfile(obj.OutputDir, num2str(folderIdx));
                
                rxFile = fullfile(currentDir, 'rx_data.mat');
                txFile = fullfile(currentDir, 'tx_data.mat');
                
                % Проверка наличия файлов
                if ~exist(rxFile, 'file') || ~exist(txFile, 'file')
                    fprintf('| %4d | %8s | %8s | %8s | %s |\n', folderIdx, '-', '-', '-', 'NO FILE');
                    continue;
                end
                
                % Загрузка данных
                rx_struct = load(rxFile, 'rx_waveform');
                tx_struct = load(txFile, 'tx_waveform', 'source_bits', 'tx_mod_symbols');
                
                rx_waveform = rx_struct.rx_waveform;
                
                % --- RECEIVER PIPELINE ---
                
                
                % 1. STF Detection
                detect = stf_h.detect(rx_waveform);
                
                if ~detect
                    fprintf('| %4d | %8s | %8s | %8s | %s |\n', folderIdx, '-', '-', '-', 'FAIL:STF');
                    continue;
                end
                
                % 2. Нарезка и CFO коррекция
                % Берем длину TX пакета как ориентир сколько резать
                len_packet = length(tx_struct.tx_waveform);
                idx_end = min(length(rx_waveform), stf_h.sto + len_packet);
                
                rx_frame = rx_waveform(stf_h.sto : idx_end);
                
                % Компенсация частоты
                t = (0 : length(rx_frame)-1).';
                rx_frame = rx_frame .* exp(-2i*pi * stf_h.cfo * t);
                
                % 3. LTF Estimation
                est = ltf_h.estimate(rx_frame);
                
                if ~est
                     fprintf('| %4d | %8s | %8s | %8.2e | %s |\n', folderIdx, '-', '-', stf_h.cfo, 'FAIL:LTF');
                     continue;
                end
                
                % 4. Data Processing
                % Смещение на начало данных (относительно начала rx_frame)
                data_start_idx = ltf_h.sto;
                
                % Расчет длины данных в сэмплах
                len_data_samples = obj.data_handler.Nsymb * (obj.data_handler.N + obj.data_handler.L);
                
                % Защита от выхода за границы массива
                if data_start_idx + len_data_samples - 1 > length(rx_frame)
                    rx_data_wav = rx_frame(data_start_idx : end);
                else
                    rx_data_wav = rx_frame(data_start_idx : data_start_idx + len_data_samples - 1);
                end
                
                % Передача эквалайзера и данных в handler
                obj.data_handler.set_eqv(ltf_h);
                
                % Для корректного расчета RMSE внутри handler (опционально)
                obj.data_handler.mod_data = tx_struct.tx_mod_symbols;
                obj.data_handler.data     = tx_struct.source_bits;
                
                [ifft_data, rx_res_data, rx_eqv_data, rx_eqv_pilots] = obj.data_handler.get_data(rx_data_wav);
                % --- СТАТИСТИКА ---
                
                % BER
                L_bits = min(length(rx_res_data), length(tx_struct.source_bits));
                ber = mean(xor(rx_res_data(1:L_bits), tx_struct.source_bits(1:L_bits)));
                
                % RMSE
                L_syms = min(length(rx_eqv_data), length(tx_struct.tx_mod_symbols));
                rmse = sqrt(mean(abs(rx_eqv_data(1:L_syms) - tx_struct.tx_mod_symbols(1:L_syms)).^2));
                
                % Вывод
                 % 1. Вывод в консоль
                fprintf('| %4d | %8.5f | %8.4f | %8.2e | %s |\n', ...
                    folderIdx, ber, rmse, stf_h.cfo, 'OK');
                
                total_ber = total_ber + ber;
                total_rmse = total_rmse + rmse;
                valid_count = valid_count + 1;
                
                % 2. Сохранение результатов в MAT (в папку пакета)
                resFile = fullfile(currentDir, 'results.mat');
                save(resFile, 'ber', 'rmse', 'stf_h');

                % 3. Сохранение в CSV (в основную директорию)
                csvPath = fullfile(obj.OutputDir, 'statistics.csv');
                
                % Открываем файл на дозапись (permission 'a')
                fid = fopen(csvPath, 'a');
                if fid ~= -1
                    % Если это первый успешный пакет, пишем заголовок
                    if valid_count == 1
                        fprintf(fid, 'FolderID,BER,RMSE,CFO_Est\n');
                    end
                    % Пишем данные
                    fprintf(fid, '%d,%.6f,%.6f,%.6e\n', folderIdx, ber, rmse, stf_h.cfo);
                    fclose(fid);
                end

                % 4. Построение и сохранение графика
                hFig = figure(1);
                % set(hFig, 'Visible', 'off'); % Раскомментируйте, чтобы окна не мелькали
                clf(hFig);
                
                t = tiledlayout(hFig, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
                
                % Левая панель: Спектрограмма
                nexttile;
                % Используем N из конфига класса
                spectrogram(rx_waveform, obj.Config.N, [], 'yaxis', 'centered');
                max_val = max(10*log10(abs(rx_waveform).^2)); % Аналог db()
                clim([max_val-50, max_val]);
                title(sprintf('Frame %d Spectrogram', folderIdx));
                
                % Правая панель: Созвездие
                % Нормировка ifft_data для отображения (как в вашем примере)
                ifft_data_plot = ifft_data ./ sqrt(mean(abs(ifft_data.^2), 'all'));
                
                nexttile;
                scatter(real(ifft_data_plot(:)), imag(ifft_data_plot(:)), 3, 'blue', '.');
                hold on;
                scatter(real(rx_eqv_data(:)), imag(rx_eqv_data(:)), 3, 'red', '.');
                scatter(real(rx_eqv_pilots(:)), imag(rx_eqv_pilots(:)), 7, 'green', '.');
                hold off;
                
                xlim([-2, 2]);
                ylim([-2, 2]);
                axis("square");
                grid on;
                title(sprintf('Constellation (BER: %.1e)', ber));
                
                % Сохранение графика в папку пакета
                plotPath = fullfile(currentDir, 'analysis_plot.png');
                exportgraphics(hFig, plotPath, 'Resolution', 150);
            end
            
            if valid_count > 0
                fprintf('|%s|\n', repmat('-', 1, 46));
                fprintf('Avg BER: %e | Avg RMSE: %f\n', total_ber/valid_count, total_rmse/valid_count);
            end
        end
        
    end
end