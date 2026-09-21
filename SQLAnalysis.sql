/*A) Derived metrics to enrich every shot*/
create or alter view dbo.v_shots_enriched as
select
	s.*,
	/* Evaluate field goal attempts */
	cast (1 as int) as FGA,
	/* Evaluate field goals made */
	case
		when s.SHOT_MADE = 1 or s.EVENT_TYPE = 'Made Shot' then 1
		else 0
	end as FGM,
	/* Evaluate 3pt field goals made */
	case
		when s.SHOT_TYPE = '3PT Field Goal'
			and (s.SHOT_MADE = 1 or s.EVENT_TYPE = 'Made Shot')
		then 1 else 0
	end as FG3M,
	/* Evaluate points scored from field goals */
	case
		when (s.SHOT_MADE in ('1', 'True', 'true') or s.EVENT_TYPE = 'Made Shot') and s.SHOT_TYPE='3PT Field Goal' then 3
		when (s.SHOT_MADE in ('1', 'True', 'true') or s.EVENT_TYPE = 'Made Shot') and s.SHOT_TYPE='2PT Field Goal' then 2
		else 0
	end as Points
from dbo.NBA_2004_2025_Shots as s;
go

/* B) League baseline by season x zone (with league zone share) */
create or alter view dbo.v_league_season_zone as
with agg as (
	select
		SEASON_1,
		BASIC_ZONE,
		sum(FGA) as FGA,
		sum(FGM) as FGM,
		sum(FG3M) as FG3M,
		sum(Points) as Points
	from dbo.v_shots_enriched
	group by SEASON_1, BASIC_ZONE
	)
select
	a.SEASON_1,
	a.BASIC_ZONE,
	a.FGA, a.FGM, a.FG3M, a.Points,
	cast(a.Points as float)/nullif(a.FGA, 0) as PPS,
	cast(a.FGM + 0.5*a.FG3M as float)/nullif(a.FGA, 0) as eFG,
	cast(a.FGA as float)/nullif(sum(a.fga) over (partition by a.season_1), 0) as league_zone_share
from agg as a;
go

/* C) Team fingerprints by season x zone */
create or alter view dbo.v_team_season_zone as
	select
		SEASON_1,
		TEAM_ID,
		TEAM_NAME,
		BASIC_ZONE,
		sum(FGA) as FGA,
		sum(FGM) as FGM,
		sum(FG3M) as FG3M,
		sum(Points) as Points
	from dbo.v_shots_enriched
	group by SEASON_1, TEAM_ID, TEAM_NAME, BASIC_ZONE;
go

/* D) Player fingerprints by season x zone */
create or alter view dbo.v_player_season_zone as
	select
		SEASON_1,
		PLAYER_ID,
		PLAYER_NAME,
		BASIC_ZONE,
		SUM(FGA) as FGA,
		SUM(FGM) as FGM,
		SUM(FG3M) as FG3M,
		SUM(Points) as Points
	from dbo.v_shots_enriched
	group by SEASON_1, PLAYER_ID, PLAYER_NAME, BASIC_ZONE;
go

/* E) Team rollup with zone share + league comparison*/
create or alter view dbo.v_team_fingerprint as
with tot as (
	select SEASON_1, TEAM_ID, sum(FGA) as teamFGA
	from dbo.v_team_season_zone
	group by SEASON_1, TEAM_ID
	)
select
	t.SEASON_1, t.TEAM_ID, t.TEAM_NAME, t.BASIC_ZONE,
	t.FGA, t.FGM, t.FG3M, t.Points,
	CAST (t.Points as float)/nullif(t.FGA,0) as PPS, /* points per shot */
	CAST (t.FGM + 0.5*t.FG3M as float)/nullif(t.FGA, 0) as eFG, /* effective FG */
	CAST (t.FGA as float)/NULLIF(tt.teamFGA,0) as zone_share, /* fraction of attempts from each zone */
	l.eFG as league_efg_zone,
	l.league_zone_share,
	(cast(t.FGM + 0.5*t.FG3M as float)/nullif(t.FGA,0)) - l.eFG as efg_vs_league_zone /* compare teams with league average */
from dbo.v_team_season_zone t
join tot tt on tt.SEASON_1 = t.SEASON_1 and tt.TEAM_ID = t.TEAM_ID
join dbo.v_league_season_zone l on l.SEASON_1 = t.SEASON_1 and l.BASIC_ZONE = t.BASIC_ZONE;
go

/* F) Player rollup with zone share and league comparison*/
create or alter view dbo.v_player_fingerprint as
with tot as (
	select SEASON_1, PLAYER_ID, sum(FGA) as playerFGA
	from dbo.v_player_season_zone
	group by SEASON_1, PLAYER_ID
	)
select
	p.SEASON_1, p.PLAYER_ID, p.PLAYER_NAME, p.BASIC_ZONE,
	p.FGA, p.FGM, p.FG3M, p.Points,
	CAST (p.Points as float)/nullif(p.FGA,0) as PPS, /* points per shot */
	CAST (p.FGM + 0.5*p.FG3M as float)/nullif(p.FGA, 0) as eFG, /* effective FG */
	CAST (p.FGA as float)/NULLIF(pt.playerFGA,0) as zone_share, /* fraction of attempts from each zone */
	l.eFG as league_efg_zone,
	l.league_zone_share,
	(cast(p.FGM + 0.5*p.FG3M as float)/nullif(p.FGA,0)) - l.eFG as efg_vs_league_zone /* compare teams with league average */
from dbo.v_player_season_zone p
join tot pt on pt.SEASON_1 = p.SEASON_1 and pt.PLAYER_ID = p.PLAYER_ID
join dbo.v_league_season_zone l on l.SEASON_1 = p.SEASON_1 and l.BASIC_ZONE = p.BASIC_ZONE;
go

/* G) Overall summary for team and player statistics by season */
CREATE OR ALTER VIEW dbo.v_team_season_summary AS
SELECT
  SEASON_1, TEAM_ID, TEAM_NAME,
  SUM(FGA) AS FGA, SUM(FGM) AS FGM, SUM(FG3M) AS FG3M, SUM(Points) AS Points,
  CAST(SUM(Points) AS float)/NULLIF(SUM(FGA),0)                     AS PPS,
  CAST(SUM(FGM)+0.5*SUM(FG3M) AS float)/NULLIF(SUM(FGA),0)          AS eFG
FROM dbo.v_team_season_zone
GROUP BY SEASON_1, TEAM_ID, TEAM_NAME;
go

CREATE OR ALTER VIEW dbo.v_player_season_summary AS
SELECT
  SEASON_1, PLAYER_ID, PLAYER_NAME,
  SUM(FGA) AS FGA, SUM(FGM) AS FGM, SUM(FG3M) AS FG3M, SUM(Points) AS Points,
  CAST(SUM(Points) AS float)/NULLIF(SUM(FGA),0)                     AS PPS,
  CAST(SUM(FGM)+0.5*SUM(FG3M) AS float)/NULLIF(SUM(FGA),0)          AS eFG
FROM dbo.v_player_season_zone
GROUP BY SEASON_1, PLAYER_ID, PLAYER_NAME;
go