POSTも走査するクローラです。

リスナを実装することで様々な処理を組み込むことができます。

	require 'web_crawler'
	
	class MyListener < CrawlerListener
	  def notify_response(result)
	  	p result
	  end
	end
	
	WebCrawler.new(MyListener.new).crawl('http://xxxxx')
