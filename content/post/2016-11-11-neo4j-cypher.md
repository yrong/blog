---
author: Ron
catalog: true
date: 2016-11-11T15:00:00Z
header-img: img/post-bg-os-metro.jpg
tags:
- neo4j
title: Neo4j Cypher query
url: /2016/11/11/neo4j-cypher/
---

### filter element

#### Delete specific element from array

[stackoverflow](http://stackoverflow.com/questions/31953794/delete-specific-element-from-array)

```
MATCH (n)
WHERE HAS(n.some_array)
SET n.array = FILTER(x IN n.some_array WHERE x <> "oranges");
```

#### split unrelated queries

[case](http://stackoverflow.com/questions/21778435/multiple-unrelated-queries-in-neo4j-cypher#comment54304565_21810903)

```
MATCH (a {cond:'1'}), (b {cond:'x'}) CREATE a-[:rel]->b
WITH 1 as dummy
MATCH (a {cond:'2'}), (b {cond:'y'}) CREATE a-[:rel]->b
WITH 1 as dummy
MATCH (a {cond:'3'}), (b {cond:'z'}) CREATE a-[:rel]->b
```

### aggregation

>	remember that anything which isn’t an aggregate function(count/collect/distinct/sum..)  
	is automaticlly used as part of the grouping key which means we could include more than  
	one field in our grouping key.

[neo4j](http://neo4j.com/docs/developer-manual/current/cypher/clauses/aggregation/)

<pre>
MATCH (n { name: 'A' })-[r]->()
RETURN <b>type(r)</b>, count(*)//group key as type(r)
</pre>

[markhneedham](http://www.markhneedham.com/blog/2013/02/17/neo4jcypher-sql-style-group-by-functionality/)

<pre>
START player = node:players('name:*')
MATCH player-[:sent_off_in]-game-[:in_month]-month
RETURN COUNT(player.name) AS numberOfReds, <b>month.name</b>//group key as month.name
ORDER BY numberOfReds DESC

START player = node:players('name:*')
MATCH player-[:sent_off_in]-game-[:in_month]-month, 
      game-[:in_match]-stats-[:stats]-player, 
      stats-[:played_for]-team
RETURN <b>month.name, team.name</b>, COUNT(player.name) AS numberOfReds//group key as month.name and team.name
ORDER BY numberOfReds DESC
</pre>

[stackoverflow](http://stackoverflow.com/questions/27536615/how-to-group-and-count-relationships-in-cypher-neo4j)

<pre>
MATCH (u:User {name: 'my user'})
RETURN <b>u</b>, size((u)-[:POSTED]>())//count posts group by user
</pre>

[stackoverflow](http://stackoverflow.com/questions/13731911/how-to-use-sql-like-group-by-in-cypher-query-language-in-neo4j)

<pre>
start n=node:node_auto_index(name='comp')
match n<-[:Members_In]-x
with  <b>n.name as companyName</b>, collect(x) as employees//group by company name
return length(filter(x in employees : x.Sex='Male')) as NumOfMale,
length(filter(x in employees : x.Sex='Female')) as NumOfFemale,
length(employees) as Total
</pre>

### collecting elments

[Neo4j Gist](http://gist.neo4j.org/?4c4ed4fef33bcf5c4b35)

```
MATCH 
    (brand:Brand)-[:CREATED_A]->(campaign:Campaign)<-->(node)
WITH 
    brand, 
    { 
        campaign : campaign, 
        nodes : COLLECT(node)
    } AS campaigns
WITH 
    { 
        brand : brand, 
        campaigns : COLLECT(campaigns)
    } AS brands
RETURN brands
```

```
match (n:Label)
//group by n.prop implicitly
with n.prop as prop, collect(n) as nodelist, count(*) as count
where count > 1
return prop, nodelist, count;
```

[markhneedham](http://www.markhneedham.com/blog/2014/09/26/neo4j-collecting-multiple-values-too-many-parameters-for-function-collect/)

```
MATCH (p:Person)-[:EVENT]->(e)
RETURN p, COLLECT({eventName: e.name, eventTimestamp: e.timestamp});
```

[stackoverflow](http://stackoverflow.com/questions/30266193/neo4j-cypher-how-to-count-multiple-property-values-with-cypher-efficiently-and)

```
match (c:Company {id: 'MY.co'})<-[:type_of]-(s:Set)<-[:job_for]-(j:Job) 
with s, j.Status as Status,count(*) as StatusCount
return s.Description, collect({Status:Status,StatusCount:StatusCount]);
```
[my movie project](https://github.com/yrong/movies-python-bolt/blob/master/movies.py)

```
MATCH (movie:Movie {title:'A League of Their Own'}) 
OPTIONAL MATCH (movie)<-[r]-(person:Person)
return movie.title as title,collect({name:person.name, type:(head(split(lower(type(r)), '_'))), roles:r.roles}) as cast
```

[markhneedham](http://www.markhneedham.com/blog/2013/03/20/neo4jcypher-with-collect-extract)

```
START team = node:teams('name:"Manchester United"')
MATCH team-[h:home_team|away_team]-game-[:on_day]-day 
WITH day.name as d, game, team, h 
MATCH team-[:home_team|away_team]-game-[:home_team|away_team]-opp 
WITH d, COLLECT([type(h),opp.name]) AS games 
RETURN d, 
  EXTRACT(c in FILTER(x in games: HEAD(x) = "home_team") : HEAD(TAIL(c))) AS home,   
  EXTRACT(c in FILTER(x in games: HEAD(x) = "away_team") : HEAD(TAIL(c))) AS away
```

### null handling

#### case&&null check

[stackoverflow](http://stackoverflow.com/questions/24487418/cypher-remove-all-properties-with-a-particular-value)

```
load csv with headers from "" as line
with line, case line.foo when '' then null else line.foo end as foo
create (:User {name:line.name, foo:foo})
```

```
MATCH (n:Asset)
WHERE n.manageIP IS NOT NULL
WITH n.manageIP as ips,n as asset
REMOVE asset.manageIP
return asset,ips
```

#### foreach check
[markhneedham](http://www.markhneedham.com/blog/2014/08/22/neo4j-load-csv-handling-empty-columns/)

```
load csv with headers from "file:/tmp/foo.csv" as row
MERGE (p:Person {a: row.a})
FOREACH(ignoreMe IN CASE WHEN trim(row.b) <> "" THEN [1] ELSE [] END | SET p.b = row.b)
FOREACH(ignoreMe IN CASE WHEN trim(row.c) <> "" THEN [1] ELSE [] END | SET p.c = row.c)
RETURN p
```

[stackoverflow](http://stackoverflow.com/questions/27576427/cypher-neo4j-case-expression-with-merge)

```
FOREACH ( i in (CASE WHEN {asset_location} IS NOT NULL and {asset_location}.status = 'mounted' THEN [1] ELSE [] END) |
   MERGE (cabinet:Cabinet {uuid:{asset_location}.cabinet})
   MERGE (n)-[:LOCATED{status:"mounted",u:{asset_location}.u,date_mounted:{asset_location}.date_mounted}]->(cabinet)
)
```

### complex json structure handling

[neo4j-blog](https://neo4j.com/blog/cypher-load-json-from-url/)

```
Overall Response Structure
{ "items": [{
    "question_id": 24620768,
    "link": "http://stackoverflow.com/questions/24620768/neo4j-cypher-query-get-last-n-elements",
    "title": "Neo4j cypher query: get last N elements",
    "answer_count": 1,
    "score": 1,
    .....
    "creation_date": 1404771217,
    "body_markdown": "I have a graph....How can I do that?",
    "tags": ["neo4j", "cypher"],
    "owner": {
        "reputation": 815,
        "user_id": 1212067,
        ....
        "link": "http://stackoverflow.com/users/1212067/"
    },
    "answers": [{
        "owner": {
            "reputation": 488,
            "user_id": 737080,
            "display_name": "Chris Leishman",
            ....
        },
        "answer_id": 24620959,
        "share_link": "http://stackoverflow.com/a/24620959",
        ....
        "body_markdown": "The simplest would be to use an ... some discussion on this here:...",
        "title": "Neo4j cypher query: get last N elements"
    }]
 }
```

```
WITH {json} as data
UNWIND data.items as q
MERGE (question:Question {id:q.question_id}) ON CREATE
  SET question.title = q.title, question.share_link = q.share_link, question.favorite_count = q.favorite_count

MERGE (owner:User {id:q.owner.user_id}) ON CREATE SET owner.display_name = q.owner.display_name
MERGE (owner)-[:ASKED]->(question)

FOREACH (tagName IN q.tags | MERGE (tag:Tag {name:tagName}) MERGE (question)-[:TAGGED]->(tag))
FOREACH (a IN q.answers |
   MERGE (question)<-[:ANSWERS]-(answer:Answer {id:a.answer_id})
   MERGE (answerer:User {id:a.owner.user_id}) ON CREATE SET answerer.display_name = a.owner.display_name
   MERGE (answer)<-[:PROVIDED]-(answerer)
)
```

### unwind vs foreach

[stackoverflow](http://stackoverflow.com/questions/30208963/how-to-create-relationship-and-merge-create-new-node-in-loop-in-neo4j)

```
MATCH (u:User {id:"2"})
unwind [{id:"21",name:"b",year:"2010"},
        {id:"41",name:"d",year:"2011"},
        {id:"51",name:"e",year:"2013"}] as user
merge (y:User {id: user.id, name: user.name,year:user.year})
MERGE (u)-[:FRIEND]->(y)
```

[markhneedham](http://www.markhneedham.com/blog/2014/05/31/neo4j-cypher-unwind-vs-foreach/)

```
WITH [{name: "Event 1", timetree: {day: 1, month: 1, year: 2014}}, 
      {name: "Event 2", timetree: {day: 2, month: 1, year: 2014}}] AS events
UNWIND events AS event
CREATE (e:Event {name: event.name})
WITH e, event.timetree AS timetree
MATCH (year:Year {year: timetree.year }), 
      (year)-[:HAS_MONTH]->(month {month: timetree.month }),
      (month)-[:HAS_DAY]->(day {day: timetree.day })
CREATE (e)-[:HAPPENED_ON]->(day)
```
[gist](https://gist.github.com/CliffordAnderson/8e2fb338cdb90994b0a4)

```
match (a {name:"Daniel"}), (b {name:"Jerry"})
with a,b
match s = shortestPath(a-[]-b)
unwind nodes(s) as n
with collect(n) as m
return head(m)
```

