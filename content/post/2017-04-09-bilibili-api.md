---
author: Ron
catalog: true
date: 2017-04-09T00:00:00Z
tags:
- crawler
title: bilibili crawler
---

针对B站视频的爬虫实现
<!--more-->

## 关于KEY
B站的key是分成两种:app-key和secret-key．之前是开放申请的，地址:http://api.bilibili.com
，目前已经关闭．只有使用之前申请过的了，具体参考一些开源项目中的引用.

有些接口不需要key就能用，key根据新旧也是有权限的，比较老的基本就能随便用，而新申请的还需要使用secret-key生成sign进行调用.

### 如何生成sign
调用接口时会需要生成sign，对于这个东西的说明是:

“把接口所需所有参数拼接，如utk=xx&time=xx，按参数名称排序，最后再拼接上密钥secret-key，做md5加密 (callback不需要参与sign校检)”

```golang
//generate bilibili sign code
query, sign := EncodeSign(params, b.Params.Secret)

func EncodeSign(params map[string]string, secret string) (string, string) {
	queryString := httpBuildQuery(params)
	return queryString, Md5(queryString + secret)
}

func httpBuildQuery(params map[string]string) string {
	list := make([]string, 0, len(params))
	buffer := make([]string, 0, len(params))
	for key := range params {
		list = append(list, key)
	}
	sort.Strings(list)
	for _, key := range list {
		value := params[key]
		buffer = append(buffer, key)
		buffer = append(buffer, "=")
		buffer = append(buffer, value)
		buffer = append(buffer, "&")
	}
	buffer = buffer[:len(buffer) - 1]
	return strings.Join(buffer, "")
}

func Md5(formal string) string {
	h := md5.New()
	h.Write([]byte(formal))
	return hex.EncodeToString(h.Sum(nil))
}
```

## 如何取得视频实际地址

### 视频详细信息->view:

获取一个视频的评论，弹幕地址，tag等等。 注意的是返回的cid很有用，之后可以取得视频实际地址。

> request

    http://api.bilibili.com/view?appkey=4ebafd7c4951b366&batch=1&check_area=1&id=10139449&platform=ios&type=json&sign=84fa5e2f209a3374b09f9604bddabe75

> response

```
{
  tid: 138,
  typename: "搞笑",
  arctype: "Original",
  play: "10181",
  review: "0",
  video_review: "268",
  favorites: "29",
  title: "【毒角SHOW】老外也有假期作业？史上最遥远距离街访Vol.17",
  description: "美帝人民槽点多~ 跨越中美两地的街访！EXCUSE ME!问点事儿~ 记得戴上耳机观看！",
  tag: "搞笑,街头访问,中美文化,外国人,原创",
  pic: "https://i0.hdslb.com/bfs/archive/a1d785aafd01c24afecbfba50d8a164149879c55.jpg",
  author: "毒角Show",
  mid: "39847479",
  face: "https://i0.hdslb.com/bfs/face/24486911dc40a0faa23b025b4493f15b086c65cc.jpg",
  pages: 1,
  created_at: "2017-04-28 01:47",
  coins: "97",
  list: {
    0: {
      page: 1,
      type: "vupload",
      part: "1",
      cid: 16753181,
      vid: 0
    }
  }
}
```

### 获取视频下载地址

这里就要用B站另外一个接口:http://interface.bilibili.tv/playurl

> request

    http://interface.bilibili.com/playurl?&appkey=f3bb208b3d081dc8&cid=16753181&from=miniplay&otype=json&player=1&quality=1&type=mp4&sign=88d94ec41b48899c6037b5435718b229

> response

```
{
    format: "mp4",
        timelength: 237192,
    accept_format: "flv,hdmp4,mp4",
    accept_quality: [
    3,
    2,
    1
    ],
    durl: [
    {
        length: 237192,
        size: 17059919,
        url: "http://ws.acgvideo.com/b/ef/16753181-1.mp4?wsTime=1493448334&platform=pc&wsSecret2=b24da826f12ee2802ffce2215370217e&oi=3730736410&rate=10",
        backup_url: null
    }
    ]
}
```

## 个人测试项目

[bilibilidownload](https://github.com/yrong/bilibilidownload)

针对原项目sign的生成方式错误做了修正

## 抓取聚合项目

[bilibi-fe](http://ronyang.tpddns.cn)

## 参考文档

[B站接口整理](https://github.com/Vespa314/bilibili-api)
