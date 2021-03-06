class PluginManager < AbstractController::Base
  include SalorBase
  include AbstractController::Rendering
  include AbstractController::Helpers
  include AbstractController::Translation
  include AbstractController::AssetPaths
  include Rails.application.routes.url_helpers
  helper ApplicationHelper
  self.view_paths = "app/views/"
  
  def initialize(current_vendor,current_company,current_user)
    @current_company        = current_company
    @current_vendor         = current_vendor
    @current_user           = current_user
    @current_plugin_manager = self
    @plugins                = Plugin.visible.where(:vendor_id => @current_vendor.id)
    @context                = V8::Context.new
    @context['Salor']       = self
    @context['Params']      = $PARAMS
    @context['Request']     = $REQUEST
    @code = nil
    # Filters are organized by name, which will be an
    # array of filters which will be sorted by their priority
    # { :some_filter => [
    # 		{:function => "my_callback"}
    # 	]
    # }
    @filters                = {}
    @hooks                  = {}
    text                    = "(function () {\nvar __plugin__ = null;\nvar plugins = {};\n"
    @plugins.each do |plugin|
    	log_action plugin.filename.current_path
      if plugin.filename.current_path and File.exists? plugin.filename.current_path
        begin
    	   File.open(plugin.filename.current_path,'r') do |f|
          text += "\n__plugin__ = #{plugin.attributes.to_json};\n";
          text += f.read
         end
        rescue => e
          log_action e.inspect
        end
      end
    end
    text += "return plugins; \n})();\n"
    begin
      @code = @context.eval(text)
    rescue => e
      log_action "Code failed to evaluate"
      log_action e.inspect
    end
  end
  def debug_obj(obj) 
    obj.each do |k,v|
      puts k.inspect
      log_action "#{k} -> #{v}"   
    end
  end
  def priority_sort(arr)
    return arr.sort {|a,b|  b[:priority] <=> a[:priority]}
  end
  def add_filter(name,function, priority=0)
    @filters[name.to_sym] ||= []
    @filters[name.to_sym].push({:function => function, :priority => priority})
    @filters[name.to_sym] = priority_sort(@filters[name.to_sym])
  end

  def add_hook(name,function,priority=0)
    @hooks[name.to_sym] ||= []
    @hooks[name.to_sym].push({:function => function, :priority => priority})
    @hooks[name.to_sym] = priority_sort(@hooks[name.to_sym])
  end

  def get_function_from(obj,path)

    if path.include? '.' then
      # I.E. The namespacing will be like this
      # my.obj.callback
      # so we split by . then reverse, then pop
      # then drill down to the callback function
      path = path.split('.').reverse
      first = path.pop
      function = obj[first]
      path.each do |fname|
        function = function[fname]
      end
    else
      function = obj[path]
    end
    return function

  end

  # Filters work more or less in the same way as WP.
  # You pass in an argument and run it through the filters
  # and then it is returned to you.
  def apply_filter(name,arg)

    return arg if not @code
    if @filters[name.to_sym] then
      @filters[name.to_sym].each do |callback|
        begin
          function_name = callback[:function]
          
          function = get_function_from(@code,function_name)
          
          if not function then
            log_action "function #{callback[:function]} is not set."
          else
            arg = function.methodcall(function,arg)
          end
          
         rescue => e
           log_action "When Applying Filter" + e.inspect
        end
      end 
    end
    return arg

  end

  def do_hook(name)

    return '' if not @code
    content = ''
    if @hooks[name.to_sym] then
      @hooks[name.to_sym].each do |callback|
        begin
          function_name = callback[:function]
          
          function = get_function_from(@code,function_name)
          
          if not function then
            log_action "function #{callback[:function]} is not set."
          else
            tmp = function.methodcall(function)
            if tmp.nil? then
              log_action "Must return a string from a hook"
            else
              content += tmp
            end
          end
          
         rescue => e
           log_action "When doing hook" + e.inspect
           log_action e.backtrace.join("\n")
        end
      end 
    end
    return content.html_safe

  end

  def render_partial(name,locals)
    vars = v8_object_to_hash(locals)
    debug_obj(vars)
    render( :partial => name, :locals => vars)
  end

  def v8_object_to_hash(src_attrs)
    attrs = {}
    log_action "Trying to convert to hash"
    if src_attrs.kind_of? V8::Object then
      src_attrs.each do |k,v|
        if v.kind_of? V8::Object then
          attrs[k.to_sym] = v8_object_to_hash(v)
        else
          attrs[k.to_sym] = v
        end
      end
    end
    return attrs
  end

end