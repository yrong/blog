---
author: Ron
catalog: false
date: 2016-07-21T15:00:00Z
tags:
- nginx
title: nginx模块初始化
---

nginx模块初始化
<!--more-->

主要在函数ngx_init_cycle（src/ngx_cycle.c）中完成

``` c
...
for (i = 0; cycle->modules[i]; i++) {
        if (cycle->modules[i]->type != NGX_CORE_MODULE) {
            continue;
        }

        module = cycle->modules[i]->ctx;

        if (module->create_conf) {
        	//只有ngx_core_module有create_conf回调函数,这个会调用函数会创建ngx_core_conf_t结构，用于存储整个配置文件main scope范围内的信息，比如worker_processes，worker_cpu_affinity等
            rv = module->create_conf(cycle);
            if (rv == NULL) {
                ngx_destroy_pool(pool);
                return NULL;
            }
            cycle->conf_ctx[cycle->modules[i]->index] = rv;
        }
    }
...

//开始解析配置文件中的每个命令,conf存放解析配置文件的上下文信息
if (ngx_conf_parse(&conf, &cycle->conf_file) != NGX_CONF_OK) {
...
}
``` 

conf结构中的module_type表示将要解析模块的类型，ctx指向解析出每个模块配信息的存放如下图所示
![](/img/nginx_conf.png)

具体看ngx_conf_parse

``` c
char *
ngx_conf_parse(ngx_conf_t *cf, ngx_str_t *filename)
{
...
     for ( ;; ) {
         rc = ngx_conf_read_token(cf);  //从配置文件中读取下一个命令
         ...
         rc = ngx_conf_handler(cf, rc);  //查找命令所在的模块，执行命令对应的函数,
         ...
         rv = cmd->set(cf, cmd, conf);
     }
     ...
}
```

命令函数在所在的模块的ngx_command_t结构中统一定义，例如ngx_http_module模块的命令函数ngx_http_block专门处理http指令

``` c
static ngx_command_t  ngx_http_commands[] = {

    { ngx_string("http"),
      NGX_MAIN_CONF|NGX_CONF_BLOCK|NGX_CONF_NOARGS,
      ngx_http_block,
      0,
      0,
      NULL },

      ngx_null_command
};
```

``` c
static char *
ngx_http_block(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
...
 	//http的main域配置
     ctx->main_conf 
     ...
     //http的server域
     ctx->srv_conf 
     ...
     //http的local域
     ctx->loc_conf 
...
	/* 递归ngx_conf_parse来调用处理http包含的块的配置信息 */

    cf->module_type = NGX_HTTP_MODULE;
    cf->cmd_type = NGX_HTTP_MAIN_CONF;
    rv = ngx_conf_parse(cf, NULL);
...
}
```
