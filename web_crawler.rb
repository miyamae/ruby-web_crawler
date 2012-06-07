require "rubygems"
require "mechanize"
require "cgi"
require "base64"

class CrawlerListener

  def notify_begin
  end

  def pre_request
  end

  def notify_response(result)
    puts %Q{#{result[:method]} #{result[:uri]} #{result[:query] ? result[:query].inspect : ""}}
  end

  def post_request
  end

  def notify_end
  end

  def result_format(result)
    s = ""
    uri = result[:uri]
    s << %Q{#{uri}\n\n}
    s << %Q{#{result[:method]} #{uri.path} HTTP/1.1\n}
    s << %Q{User-Agent: #{result[:user_agent]}\n}
    s << %Q{Referer: #{result[:referer]}\n}
    if result[:authorization]
      s << %Q{Authorization: Basic #{result[:authorization]}\n}
    end
    if result[:query]
      qstr = ""
      result[:query].each {|q|
        qstr << CGI.escape(q[0]) + "=" + CGI.escape(q[1]) + "&"
      }
      qstr.chop!
      s << %Q{Content-Length: #{qstr.length}\n}
      s << qstr
    end
    s << %Q{\n}
    s << %Q{HTTP/1.x #{result[:code]}\n}
    if result[:header]
      result[:header].each {|h|
        if h[0].downcase == "set-cookie"
          s << %Q{#{h[0]}: #{h[1].gsub(/expires=.*?GMT(,\s*|$)/, '')}\n}
        else
          s << %Q{#{h[0]}: #{h[1]}\n}
        end
      }
    end
    s << %Q{----------------------------------------------------------\n}
    s
  end
end

class WebCrawler

  PRODUCT = "BitArts Crawler 1.0.5"

  attr_accessor :listener, :results, :excludes
  attr_accessor :proxy_host, :proxy_port, :username, :password

  def initialize(listener=CrawlerListener.new)
    @crawled = {}
    @listener = listener
    @excludes = /\.(jpg|png|gif|js|css|ico)(\??\d*)$/i
  end

private

  def create_agent
    agent = Mechanize.new
    @user_agent = "Mozilla/4.0 (compatible; MSIE 7.0; Windows NT 5.1; #{PRODUCT})"
    agent.user_agent = @user_agent
    if @proxy_host
      agent.set_proxy(@proxy_host, @proxy_port)
    end
    agent.auth(username, password)
    agent
  end

  def http_request(method, uri, query={})
    agent = create_agent
    begin
      if method == "GET"
        page = agent.get(uri, query)
      elsif method == "POST"
        page = agent.post(uri, query)
      end
      agent.page.encoding = "UTF-8"
      page
    rescue
      nil
    end
  end

  def get_links(page)
    links = []
    (page.links + page.meta + page.frames + page.iframes).each {|link|
      begin
        if link.uri
          links << page.uri + link.uri
        end
      rescue URI::InvalidURIError
      end
    }
    imgsrcs = page.root.search("img").map{|e| e["src"]}
    imgsrcs.each {|uri|
      begin
        links << page.uri + uri
      rescue Exception => e
      end
    }
    links
  end

  def child_uri?(uri)
    uri.to_s.index(@root_uri.to_s.gsub(/\/[^\/]*?$/, "/")) == 0
  end

  def crawl_r(uri, referer=nil, query=nil, method="GET")
    return false unless child_uri?(uri)
    key = %Q{#{method} #{uri.to_s.gsub(/\/$/,"")} #{query ? query.inspect : ""}}
    if @crawled.has_key?(key)
      return
    else
      @crawled[key] = true
    end
    result = {}
    return false if uri.to_s =~ @excludes
    @listener.pre_request
    page = http_request(method, uri, query)
    @listener.post_request
    result = {
      :method => method,
      :uri => uri,
      :query => query,
      :referer => referer,
      :user_agent => @user_agent
    }
    if username
      result[:authorization] = Base64.encode64("#{username}:#{password}")
    end
    if page
      result.update({
        :page => page,
        :code => page.code,
        :body => page.body,
        :header => page.response
      })
    end
    @listener.notify_response(result)
    @results << result
    if page.is_a?(Mechanize::Page)
      links = get_links(page)
      links.each {|u|
        u.fragment = nil
        unless @uris.has_key?(u.to_s)
          @uris[u.to_s] = true
          crawl_r(u, uri)
        end
      }
      page.forms.each {|f|
        u = page.uri + f.action
        k = u.to_s + "?" + f.request_data
        f.build_query.each do |k, v|
          if u.query && u.query.include?(k)
            u.query.gsub!(/#{Regexp.escape(k)}=.*?[&$]/, "")
          end
        end
        unless @uris.has_key?(k)
          @uris[k] = true
          crawl_r(u, uri, f.build_query, f.method)
        end
      }
    end
    true
  end

public

  def crawl(uri)
    @uris = {}
    @results = []
    @root_uri = uri.is_a?(URI) ? uri : URI.parse(uri)
    @root_uri.path = "/" if @root_uri.path.empty?
    @listener.notify_begin
    crawl_r(@root_uri)
    @listener.notify_end
    true
  end

end
