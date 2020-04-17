---
author: Ron
catalog: false
date: 2016-10-13T18:00:00Z
tags:
- elasticsearch
title: ElasticSearch Query DSL
---

ElasticSearch Query DSL Examples
<!--more-->

ElasticSearch Query DSL Examples
=============================


> * 加载[ik](https://github.com/medcl/elasticsearch-analysis-ik)分词插件,配置开启inline脚本

```
script.inline: true
script.indexed: true
```

> * 建索引

```bash
curl -XDELETE 'localhost:9200/text'
curl -XPUT 'localhost:9200/text?pretty'
```

> * mapping定义

```bash
curl -XPOST http://localhost:9200/text/mytext/_mapping -d'
{
    "mytext": {  
        "_all": {
            "analyzer": "ik_max_word",
            "search_analyzer": "ik_max_word",
            "term_vector": "no",
            "store": "false"
        },
        "properties": {
            "content": {
                "type": "string",
                "analyzer": "ik_max_word",
                "search_analyzer": "ik_max_word",
                "include_in_all": "true",
                "boost": 8
            },
            "ttl": {
          		"properties": {"$date": { "type": "date"}}
        	}
    }
    }
}'
```

> * 导入测试数据

```bash
curl -XPUT 'localhost:9200/text/mytext/5?pretty' -d'
{"url": "sina.com","content":"今年反正我都会避让，不给自己找麻烦","ch":7,"it":14361982,"appid":{"$numberLong":"1"},"ttl":{"$date":"2015-07-09T23:59:40.631+0800"}
}
'

curl -XPUT 'localhost:9200/text/mytext/6?pretty' -d'
{"url": "baidu.com","content":"今年在上海租房火爆","ch":8,"it":14361982,"appid":{"$numberLong":"1"},"ttl":{"$date":"2015-07-09T23:59:40.631+0800"}
}
'

curl -XPUT 'localhost:9200/text/mytext/7?pretty' -d'
{"url": "baidu.com","content":"今年在南京租房火爆","ch":8,"it":14361982,"appid":{"$numberLong":"1"},"ttl":{"$date":"2015-07-09T23:59:40.631+0800"}
}
'
```

### [bucket-selector-aggregation](https://www.elastic.co/guide/en/elasticsearch/reference/master/search-aggregations-pipeline-bucket-selector-aggregation.html) & [bucket-script-aggregation](https://www.elastic.co/guide/en/elasticsearch/reference/master/search-aggregations-pipeline-bucket-script-aggregation.html) ###

context包含“今年”，按url聚合，聚合数>1,order by聚合数，时间范围15/7/9-16/1/7

```bash
curl -XPOST 'localhost:9200/text/_search?pretty' -d'
{
  "query" : {
    "bool": {
      "must":[
      {"match":  { "content" : "今年" }},
      {"range":  {"ttl.$date" : {"gt" : "2015-07-09","lt" : "2016-01-07"}}}
        ] 
    }
  },
  "aggs": {
    "urls": {
      "terms": {
        "field": "url",
        "order" : { "_count" : "asc"}
      }, 
      "aggs": {
        "greater_than_filter": {
          "bucket_selector": {
            "buckets_path": {
              "url_count": "_count"
            }, 
            "script": "url_count > 1"
          }
        }
      }
    }
  },
  "size": 0
}
'
```

### [query-time-boosting](https://www.elastic.co/guide/en/elasticsearch/guide/current/query-time-boosting.html) ###

content包含租房，上海加权因子10，南京加权因子1

```bash
curl -XGET 'localhost:9200/text/_search?pretty' -d'
{
    "query": {
        "bool": {
            "must": {
                "match": {
                    "content": "租房"
                }
            },
            "should": [ 
                { "match": { "content": {"query": "上海",
                        "boost": 10 }}},
                { "match": { "content": {"query": "南京",
                        "boost": 1} }}
            ] 
      }
}}'
```

### [Phrase Matching](https://www.elastic.co/guide/en/elasticsearch/guide/current/slop.html) ###

content包含“反正”和“避让”，间隔不超10词

```Bash
curl -XGET 'localhost:9200/text/_search?pretty' -d'
{
    "query": {
        "match_phrase": {
            "content": {
                "query": "反正 避让",
                "slop":  10
            }
        }
    }
}
'
```
