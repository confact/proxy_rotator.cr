require "./client"
class HTTP::Proxy::Server < HTTP::Server
  class Context < HTTP::Server::Context
    def perform
      proxy_address = Proxylist::Getter.get_proxy
      proxy_server = proxy_address[0]
      proxy_port = proxy_address[1]
      username = proxy_address[2]
      password = proxy_address[3]
      # perform only once
      return if @performed
      @performed = true
      case @request.method
      when "OPTIONS"
        @response.headers["Allow"] = "OPTIONS,GET,HEAD,POST,PUT,DELETE,CONNECT"
      when "CONNECT"
        host, port = @request.resource.split(":", 2)
        upstream = TCPSocket.new(proxy_server, proxy_port)
        upstream.sync = true

        upstream << "CONNECT #{host}:#{port} HTTP/1.1\r\n"
        puts "CONNECT #{host}:#{port} HTTP/1.1\r\n"
        #upstream << "Host: #{host}\r\n"
        #puts "Host: #{host}\r\n"

        unless username.blank?
          credentials = Base64.strict_encode("#{username}:#{password}")
          credentials = "#{credentials}\n".gsub(/\s/, "")
          upstream << "Proxy-Authorization: Basic #{credentials}\r\n"
          puts "Proxy-Authorization: Basic #{credentials}\r\n"
        end

        #upstream << "\r\n"

        @response.reset
        @response.upgrade do |downstream|
          downstream = downstream.as(TCPSocket)
          downstream.sync = true

          #message = downstream.gets
          #puts message

          spawn do
            #spawn { IO.copy(upstream, STDOUT) }
            spawn { IO.copy(downstream, STDOUT) }
            spawn { IO.copy(upstream, downstream) }
            spawn { IO.copy(downstream, upstream) }
          end
        end
      else
        proxy_client = HTTP::Proxy::Client.new(proxy_server, proxy_port.to_i, username, password)
        uri = URI.parse @request.resource
        client = HTTP::Client.new(uri)
        client.set_proxy(proxy_client)
        response = client.exec(@request)
        @request.headers.delete("Accept-Encoding")
        response.headers.add("X-PROXY-IP", proxy_server)
        response.headers.delete("Transfer-Encoding")
        response.headers.delete("Content-Encoding")
        @response.headers.merge! response.headers
        @response.status_code = response.status_code
        @response.print response.body
      end
    end
  end
end
