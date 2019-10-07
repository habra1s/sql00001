-- FreeDiskSpaceStatus v.03.04.2013 for blog
-- 2013, ����� �������, http://imamyshev.wordpress.com
-- ������ ��� SQL Server 2008 R2, 2012
-- ���������� � �������� �� ��������� �������� ������������� �� ��������� �������
-- ���������� email � ������ ����������� ��������
--
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
GO
EXEC sp_configure 'xp_cmdshell', 1;
RECONFIGURE;
GO

SET NOCOUNT ON

-- �������� ����������
DECLARE @FreeSpaceLimit int,
@email varchar(128);

-- ��������� �������� ����������
SET @FreeSpaceLimit = 20 -- ����������� ����� ���������� ��������� ������������ � ���������
SET @email = 'logs@domain.ru' -- �� ��� ������ ��������� �������� ����������� (��������� ������� ��������� ������ ";")
-- ������� ��������� �������
IF (object_id('tempdb..##SENDMAIL_TEMP_TBL') IS not null) DROP TABLE ##SENDMAIL_TEMP_TBL

-- �������� ���������� � ������
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
-- �������� � ���������� ��������� ������� ��� ����������� �������� �� email
SELECT drive as [drive], ROUND(free_bytes/1024/1024/1024,2) as [free_gb], ROUND(total_bytes/1024/1024/1024,2) as [total_gb] , ROUND(free_bytes*100/total_bytes,2) as [percent_free]
INTO ##SENDMAIL_TEMP_TBL
FROM @drives_info
-- ������� ���������� ������ ��� ����������
SELECT * FROM ##SENDMAIL_TEMP_TBL

-- ���� ���� ���� �� ���� ���� � ������� ���������� ������������ ����� ������, ��..
IF (select min (free_bytes*100/total_bytes) from @drives_info)<@FreeSpaceLimit
	BEGIN
	SELECT '���� ���������� ��� ��������. ����� ��������� email..';
	-- ���������� email ���������� =============================
	SET NOCOUNT ON
	-- �������� ����������
	DECLARE @subject_str varchar(255),
	@message_str varchar(max),
	@separator_str varchar(1)
	-- ��������� �������� ����������
	SET @separator_str=CHAR(9) -- ������ ���������
	-- ���������� ����� ���������
	SET @subject_str = 'SQL Server '+@@SERVERNAME+': Free Disk Space Status'
	SET @message_str = N'
	<html><body>
	<head></head>
	<table><tr><td><font color=black>
	���������� �������� �� ��������� �������� �������������!<br>
	�� ����� ��� ���������� ��������� ������ ������� '+@@SERVERNAME+N' ����� ��� '+(SELECT CONVERT(varchar,@FreeSpaceLimit))+N'% ���������� ������������.<br>
	����� ������������: ' + (SELECT CONVERT(varchar,GETDATE(),104)) + ' ' + (SELECT CONVERT(varchar,GETDATE(),108)) +
	N'</font></td></tr></table>
	<table border="1" cellpadding="3" cellspacing="0">
	<tr bgcolor=gray><td>����</td><td>��������, GB</td><td>�����, GB</td><td>% ��������</td></tr>' + (
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
	����� ������������ �� SQL Server '+@@SERVERNAME+N'<br>
	</font></td></tr></table>
	</body></html>
	'
	-- ���������� email
	EXEC msdb.dbo.sp_send_dbmail
	@recipients = @email,
	@subject = @subject_str,
	@body = @message_str,
	@body_format = 'HTML',
	@query_result_width = 1024,
	@query_result_separator = @separator_str
	-- ���������� email ���������� =============================
	END
	ELSE SELECT '��� ���������� ��� ��������.';
-- ������� ��������� �������
IF (object_id('tempdb..##SENDMAIL_TEMP_TBL') IS not null) DROP TABLE ##SENDMAIL_TEMP_TBL