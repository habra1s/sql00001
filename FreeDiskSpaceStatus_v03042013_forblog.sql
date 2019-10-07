-- FreeDiskSpaceStatus v.03.04.2013 for blog
-- 2013, Илгиз Мамышев, http://imamyshev.wordpress.com
-- Версия для SQL Server 2008 R2, 2012
-- Оповещение о проблеме со свободным дисковым пространством на локальном сервере
-- Отправляем email в случае обнаружения проблемы
--
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
GO
EXEC sp_configure 'xp_cmdshell', 1;
RECONFIGURE;
GO

SET NOCOUNT ON

-- Создадим переменные
DECLARE @FreeSpaceLimit int,
@email varchar(128);

-- Определим значения переменных
SET @FreeSpaceLimit = 20 -- Минимальный объём свободного дискового пространства в процентах
SET @email = 'logs@domain.ru' -- На эти адреса выполнить рассылку уведомления (несколько адресов разделить знаком ";")
-- Удаляем временную таблицу
IF (object_id('tempdb..##SENDMAIL_TEMP_TBL') IS not null) DROP TABLE ##SENDMAIL_TEMP_TBL

-- Получаем информацию о дисках
declare @drives table (drive char(1), free int)
insert into @drives exec xp_fixeddrives

declare @drive char(1), @str varchar(255)
declare @tmp table (cmd_output varchar(255))
declare @drives_info table (drive char(1), free_bytes float, total_bytes float)

declare cur cursor local fast_forward
for select drive from @drives order by drive

open cur
fetch next from cur into @drive

while @@fetch_status = 0
begin
	delete from @tmp
	set @str = 'exec xp_cmdshell ''fsutil volume diskfree ' + @drive + ':'''	
	insert into @tmp exec (@str)
	
	insert into @drives_info
	select
		@drive,
		substring(t1.cmd_output, charindex(':', t1.cmd_output) + 2, len(t1.cmd_output) - charindex(':', t1.cmd_output) - 1),
		substring(t2.cmd_output, charindex(':', t2.cmd_output) + 2, len(t2.cmd_output) - charindex(':', t2.cmd_output) - 1)
        from @tmp t1, @tmp t2
	where t1.cmd_output like 'Total # of free bytes%' and t2.cmd_output like 'Total # of bytes%'

	fetch next from cur into @drive
end
close cur
deallocate cur
-- Сохраним в глобальную временную таблицу для последующей отправки по email
SELECT drive as [drive], ROUND(free_bytes/1024/1024/1024,2) as [free_gb], ROUND(total_bytes/1024/1024/1024,2) as [total_gb] , ROUND(free_bytes*100/total_bytes,2) as [percent_free]
INTO ##SENDMAIL_TEMP_TBL
FROM @drives_info
-- Выводим полученные данные для тображения
SELECT * FROM ##SENDMAIL_TEMP_TBL

-- Если есть хотя бы один диск с объёмом свободного пространства менее лимита, то..
IF (select min (free_bytes*100/total_bytes) from @drives_info)<@FreeSpaceLimit
	BEGIN
	SELECT 'Есть информация для рассылки. будет отправлен email..';
	-- Отправляем email оповещение =============================
	SET NOCOUNT ON
	-- Создадим переменные
	DECLARE @subject_str varchar(255),
	@message_str varchar(max),
	@separator_str varchar(1)
	-- Определим значения переменных
	SET @separator_str=CHAR(9) -- Символ табуляции
	-- Подготовим текст сообщения
	SET @subject_str = 'SQL Server '+@@SERVERNAME+': Free Disk Space Status'
	SET @message_str = N'
	<html><body>
	<head></head>
	<table><tr><td><font color=black>
	Обнаружена проблема со свободным дисковым пространством!<br>
	На одном или нескольких локальных дисках сервера '+@@SERVERNAME+N' менее чем '+(SELECT CONVERT(varchar,@FreeSpaceLimit))+N'% свободного пространства.<br>
	Отчёт сгенерирован: ' + (SELECT CONVERT(varchar,GETDATE(),104)) + ' ' + (SELECT CONVERT(varchar,GETDATE(),108)) +
	N'</font></td></tr></table>
	<table border="1" cellpadding="3" cellspacing="0">
	<tr bgcolor=gray><td>Диск</td><td>Свободно, GB</td><td>Всего, GB</td><td>% Свободно</td></tr>' + (
	select
	  (select stt.[drive] as 'td' for xml path(''), type),
	  (select cast(stt.[free_gb] as nvarchar) as 'td' for xml path(''), type),
	  (select cast(stt.[total_gb] as nvarchar) as 'td' for xml path(''), type),
	  (select cast(stt.[percent_free] as nvarchar) as 'td' for xml path(''), type)
	from ##SENDMAIL_TEMP_TBL as stt
	order by [drive],[free_gb],[total_gb],[percent_free]
	for xml path('tr')
	) + N'</table>
	<table><tr><td>
	<font color=gray>
	Отчёт сгенерирован на SQL Server '+@@SERVERNAME+N'<br>
	</font></td></tr></table>
	</body></html>
	'
	-- Отправляем email
	EXEC msdb.dbo.sp_send_dbmail
	@recipients = @email,
	@subject = @subject_str,
	@body = @message_str,
	@body_format = 'HTML',
	@query_result_width = 1024,
	@query_result_separator = @separator_str
	-- Отправляем email оповещение =============================
	END
	ELSE SELECT 'Нет информации для рассылки.';
-- Удаляем временную таблицу
IF (object_id('tempdb..##SENDMAIL_TEMP_TBL') IS not null) DROP TABLE ##SENDMAIL_TEMP_TBL