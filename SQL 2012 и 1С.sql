USE [master]
GO

/****** Object:  StoredProcedure [dbo].[sp_dboption]    Script Date: 21.03.2012 7:33:37 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE procedure [dbo].[sp_dboption]	-- 1999/08/09 18:25
	@dbname sysname = NULL,			-- database name to change
	@optname varchar(35) = NULL,	-- option name to turn on/off
	@optvalue varchar(10) = NULL	-- true or false
as
	set nocount    on

	declare @dbid int			-- dbid of the database
	declare @catvalue int		-- number of category option
	declare @optcount int		-- number of options like @optname
	declare @allstatopts int	-- bit map off all options stored in sysdatqabases.status
								-- that can be set by sp_dboption.
	declare @alloptopts int		-- bit map off all options stored in sysdatqabases.status
								-- that can be set by sp_dboption.
	declare @allcatopts int		-- bit map off all options stored in sysdatqabases.category
								-- that can be set by sp_dboption.
	declare @exec_stmt nvarchar(max)
	declare @fulloptname varchar(35)
	declare @alt_optname varchar(50)
	declare @alt_optvalue varchar(30)
	declare @optnameIn varchar(35)
	
	select @optnameIn = @optname
		   ,@optname = LOWER (@optname collate Latin1_General_CI_AS)

	-- If no @dbname given, just list the possible dboptions.
	--  Only certain status bits may be set or cleared by sp_dboption.

	-- Get bitmap of all options that can be set by sp_dboption.
	select @allstatopts=number from master.dbo.spt_values where type = 'D'
		and name = 'ALL SETTABLE OPTIONS'

	select @allcatopts=number from master.dbo.spt_values where type = 'DC'
		and name = 'ALL SETTABLE OPTIONS'

	select @alloptopts=number from master.dbo.spt_values where type = 'D2'
		and name = 'ALL SETTABLE OPTIONS'

	if @dbname is null
	begin
		select 'Settable database options:' = name
			from master.dbo.spt_values
			where (type = 'D'
				and number & @allstatopts <> 0
				and number not in (0,@allstatopts))	-- Eliminate non-option entries
			 or (type = 'DC'
				and number & @allcatopts <> 0
				and number not in (0,@allcatopts))
			 or (type = 'D2'
				and number & @alloptopts <> 0
				and number not in (0,@alloptopts))
			order by name
		return (0)
	end

	--  Verify the database name and get info
	select @dbid = dbid
		from master.dbo.sysdatabases
		where name = @dbname

	--  If @dbname not found, say so and list the databases.
	if @dbid is null
	begin
		raiserror(15010,-1,-1,@dbname)
		print ' '
		select 'Available databases:' = name
			from master.dbo.sysdatabases
		return (1)
	end

	-- If no option was supplied, display current settings.
	if @optname is null
	begin
		select 'The following options are set:' = v.name
			from master.dbo.spt_values v, master.dbo.sysdatabases d
			where d.name=@dbname
				   and ((number & @allstatopts <> 0
						 and number not in (-1,@allstatopts)
						 and v.type = 'D'
						 and (v.number & d.status)=v.number)
					 or (number & @allcatopts <> 0
						 and number not in (-1,@allcatopts)
						 and v.type = 'DC'
						 and d.category & v.number <> 0)
					 or (number & @alloptopts <> 0
						 and number not in (-1,@alloptopts)
						 and v.type = 'D2'
						 and d.status2 & v.number <> 0))
		return(0)
	end

	if @optvalue is not null and lower(@optvalue) not in ('true', 'false', 'on', 'off')
	begin
		raiserror(15241,-1,-1)
		return (1)
	end

	--  Use @optname and try to find the right option.
	--  If there isn't just one, print appropriate diagnostics and return.
	select @optcount = count(*) ,@fulloptname = min(name)
		from master.dbo.spt_values
		where lower(name collate Latin1_General_CI_AS) like '%' + @optname + '%'
			and ((type = 'D'
				  and number & @allstatopts <> 0
				  and number not in (-1,@allstatopts))
				or (type = 'DC'
					  and number & @allcatopts <> 0
					  and number not in (-1,@allcatopts))
				or (type = 'D2'
					  and number & @alloptopts <> 0
					  and number not in (-1,@alloptopts)))

	--  If no option, show the user what the options are.
	if @optcount = 0
	begin
		raiserror(15011,-1,-1,@optnameIn)
		print ' '

		select 'Settable database options:' = name
			from master.dbo.spt_values
			where (type = 'D'
					and number & @allstatopts <> 0
					and number not in (-1,@allstatopts)) -- Eliminate non-option entries
				or (type = 'DC'
					and number & @allcatopts <> 0
					and number not in (-1,@allcatopts))
				or (type = 'D2'
					and number & @alloptopts <> 0
					and number not in (-1,@alloptopts))
			order by name

		return (1)
	end

	--  If more than one option like @optname, show the duplicates and return.
	if @optcount > 1
	begin
		raiserror(15242,-1,-1,@optnameIn)
		print ' '

		select duplicate_options = name
		from master.dbo.spt_values
		where lower(name collate Latin1_General_CI_AS) like '%' + @optname + '%'
			and ((type = 'D'
				 and number & @allstatopts <> 0
				 and number not in (-1,@allstatopts))
			  or (type = 'DC'
				 and number & @allcatopts <> 0
				 and number not in (-1,@allcatopts))
			  or (type = 'D2'
				 and number & @alloptopts <> 0
				 and number not in (-1,@alloptopts))
			)
		return (1)
	end

	--  Just want to see current setting of specified option.
	if @optvalue is null
	begin
		select OptionName = v.name,
			CurrentSetting = (case
				  when ( ((v.number & d.status) = v.number
						  and v.type = 'D')
					  or (d.category & v.number <> 0
						   and v.type = 'DC')
					  or (d.status2 & v.number <> 0
						   and v.type = 'D2')
					   )
					 then 'ON'
				  when not
					   ( ((v.number & d.status) = v.number
						  and v.type = 'D')
					  or (d.category & v.number <> 0
						   and v.type = 'DC')
					  or (d.status2 & v.number <> 0
						   and v.type = 'D2')
					   )
					 then 'OFF'
			   end)
			from master.dbo.spt_values v, master.dbo.sysdatabases d
			where d.name=@dbname
			   and ((v.number & @allstatopts <> 0
					 and v.number not in (-1,@allstatopts)	-- Eliminate non-option entries
					 and v.type = 'D')
				 or (v.number & @allcatopts <> 0
					 and v.number not in (-1,@allcatopts)	-- Eliminate non-option entries
					 and v.type = 'DC')
				 or (v.number & @alloptopts <> 0
					 and v.number not in (-1,@alloptopts)	-- Eliminate non-option entries
					 and v.type = 'D2')
				   )
				and lower(v.name) = lower(@fulloptname)

		return (0)
	end

	select @catvalue = 0
	select @catvalue = number
		  from master.dbo.spt_values
		  where lower(name) = lower(@fulloptname)
		  and type = 'DC'

	-- if setting replication option, call sp_replicationdboption directly
	if (@catvalue <> 0)
	begin
		select @alt_optvalue = (case lower(@optvalue)
				when 'true' then 'true'
				when 'on' then 'true'
				else 'false'
			end)

		select @alt_optname = (case @catvalue
				when 1 then 'publish'
				when 2 then 'subscribe'
				when 4 then 'merge publish'
				else quotename(@fulloptname, '''')
			end)

		select @exec_stmt = quotename(@dbname, '[')   + '.dbo.sp_replicationdboption'

		EXEC @exec_stmt @dbname, @alt_optname, @alt_optvalue
		return (0)
	end


	-- call Alter Database to set options

	-- set option value in alter database
	select @alt_optvalue = (case lower(@optvalue)
			when 'true'	then 'ON'
			when 'on'	then 'ON'
			else 'OFF'
		end)

	-- set option name in alter database
	select @fulloptname = lower(@fulloptname)
	select @alt_optname = (case @fulloptname
			when 'auto create statistics' then 'AUTO_CREATE_STATISTICS'
			when 'auto update statistics' then 'AUTO_UPDATE_STATISTICS'
			when 'autoclose' then 'AUTO_CLOSE'
			when 'autoshrink' then 'AUTO_SHRINK'
			when 'ansi padding' then 'ANSI_PADDING'
			when 'arithabort' then 'ARITHABORT'
			when 'numeric roundabort' then 'NUMERIC_ROUNDABORT'
			when 'ansi null default' then 'ANSI_NULL_DEFAULT'
			when 'ansi nulls' then 'ANSI_NULLS'
			when 'ansi warnings' then 'ANSI_WARNINGS'
			when 'concat null yields null' then 'CONCAT_NULL_YIELDS_NULL'
			when 'cursor close on commit' then 'CURSOR_CLOSE_ON_COMMIT'
			when 'torn page detection' then 'TORN_PAGE_DETECTION'
			when 'quoted identifier' then 'QUOTED_IDENTIFIER'
			when 'recursive triggers' then 'RECURSIVE_TRIGGERS'
			when 'default to local cursor' then 'CURSOR_DEFAULT'
			when 'offline' then (case @alt_optvalue when 'ON' then 'OFFLINE' else 'ONLINE' end)
			when 'read only' then (case @alt_optvalue when 'ON' then 'READ_ONLY' else 'READ_WRITE' end)
			when 'dbo use only' then (case @alt_optvalue when 'ON' then 'RESTRICTED_USER' else 'MULTI_USER' end)
			when 'single user' then (case @alt_optvalue when 'ON' then 'SINGLE_USER' else 'MULTI_USER' end)
			when 'select into/bulkcopy' then 'RECOVERY'
			when 'trunc. log on chkpt.' then 'RECOVERY'
			when 'db chaining' then 'DB_CHAINING'
			else @alt_optname
		end)

	if @fulloptname = 'dbo use only'
	begin
		if @alt_optvalue = 'ON'
		begin
			if databaseproperty(@dbname, 'IsSingleUser') = 1
			begin
				raiserror(5066,-1,-1);
				return (1)
			end
		end
		else
		begin
			if databaseproperty(@dbname, 'IsDBOOnly') = 0
				return (0)
		end
	end

	if @fulloptname = 'single user'
	begin
		if @alt_optvalue = 'ON'
		begin
			if databaseproperty(@dbname, 'ISDBOOnly') = 1
			begin
				raiserror(5066,-1,-1);
				return (1)
			end
		end
		else
		begin
			if databaseproperty(@dbname, 'IsSingleUser') = 0
				return (0)
		end
	end

	select @alt_optvalue = (case @fulloptname
		when 'default to local cursor' then (case @alt_optvalue when 'ON' then 'LOCAL' else 'GLOBAL' end)
		when 'offline' then ''
		when 'read only' then ''
		when 'dbo use only' then ''
		when 'single user' then ''
		else  @alt_optvalue
	end)

	if lower(@fulloptname) = 'select into/bulkcopy'
	begin
		if @alt_optvalue = 'ON'
		begin
			if databaseproperty(@dbname, 'IsTrunclog') = 1
				select @alt_optvalue = 'RECMODEL_70BACKCOMP'
			else
				select @alt_optvalue = 'BULK_LOGGED'
		end
		else
		begin
			if databaseproperty(@dbname, 'IsTrunclog') = 1
				select @alt_optvalue = 'SIMPLE'
			else
				select @alt_optvalue = 'FULL'
		end
	end

	if lower(@fulloptname) = 'trunc. log on chkpt.'
	begin
		if @alt_optvalue = 'ON'
		begin
			if databaseproperty(@dbname, 'IsBulkCopy') = 1
				select @alt_optvalue = 'RECMODEL_70BACKCOMP'
			else
				select @alt_optvalue = 'SIMPLE'
		end
		else
		begin
			if databaseproperty(@dbname, 'IsBulkCopy') = 1
				select @alt_optvalue = 'BULK_LOGGED'
			else
				select @alt_optvalue = 'FULL'
		end
	end

	-- construct the ALTER DATABASE command string
	select @exec_stmt = 'ALTER DATABASE ' + quotename(@dbname) + ' SET ' + @alt_optname + ' ' + @alt_optvalue + ' WITH NO_WAIT'
	EXEC (@exec_stmt)

	if @@error <> 0
	begin
		raiserror(15627,-1,-1)
		return (1)
	end

	return (0) -- sp_dboption

GO


