# 致知官网（审核用一页站）

给微信开放平台 / App Store 审核看的介绍页。不是产品站。

本地文件在本目录。线上目前挂在已有证书的域名：

`https://api.knowellcards.com/`

开放平台「应用官网」先填这个地址。根域名 `knowellcards.com` 还没有解析，解析到 `47.82.115.162` 后再把同一目录挂上去。

更新：

```bash
rsync -av --delete ./site/ knowell-hk:/tmp/knowell-web/
ssh knowell-hk 'sudo rsync -a --delete /tmp/knowell-web/ /var/www/knowellcards/'
```
