# coding: UTF-8

# Salor -- The innovative Point Of Sales Software for your Retail Store
# Copyright (C) 2012-2013  Red (E) Tools LTD
# 
# See license.txt for the license applying to all files within this software.
class VendorsController < ApplicationController
  
  after_filter :customerscreen_push_notification, :only => [:edit_field_on_child]

  # TODO: This needs to be scoped for SAAS
  def csv
    @vendor = Vendor.find_by_token(params[:token])
    if @vendor then
      @items = Item.where(["vendor_id =? and hidden != 1",@vendor.id])
      @categories = Category.where(["vendor_id =? and hidden != 1",@vendor.id])
      @buttons = Button.where(["vendor_id =? and hidden != 1",@vendor.id]) if @vendor.salor_configuration.csv_buttons
      @discounts = Discount.where(["vendor_id =? and hidden IS FALSE OR hidden IS NULL",@vendor.id]) if @vendor.salor_configuration.csv_discounts
      @customers = Customer.where(["vendor_id =? and hidden != 1",@vendor.id]) if @vendor.salor_configuration.csv_customers
    end
    render :layout => false
  end
  
  def index
    @vendors = @current_user.vendors.visible
  end

  def show
    @vendor = @current_user.vendors.visible.find_by_id(params[:id])
    session[:vendor_id] = @vendor.id
  end

  def new
    @vendor = Vendor.new
  end

  def edit
    @vendor = @current_user.vendors.visible.find_by_id(params[:id])
    session[:vendor_id] = @vendor.id
  end

  def create
    @vendor = Vendor.new(params[:vendor])
    @vendor.company = @current_company
    @vendor.users = [@current_user]
    if @vendor.save
      redirect_to vendors_path
    else
      render :new
    end
  end


  def update
    @vendor = @current_user.vendors.visible.find_by_id(params[:id])
    if @vendor.update_attributes(params[:vendor])
      redirect_to vendor_path(@vendor)
    else
      render :edit
    end
  end

  def new_drawer_transaction
    amount_cents = SalorBase.string_to_float(params[:transaction][:amount], :locale => @region) * 100
    if params[:transaction][:trans_type] == "payout"
      amount_cents *= -1
    end
    @dt = @current_user.drawer_transact(amount_cents, @current_register, params[:transaction][:tag], params[:transaction][:notes])
  end

  def open_cash_drawer
    @current_register.open_cash_drawer
    render :nothing => true
  end
  
  def render_open_cashdrawer
    render :text => @current_register.open_cash_drawer_code
  end

  def render_drawer_transaction_receipt
    @dt = @current_vendor.drawer_transactions.visible.find_by_id(params[:id])
    if @current_register.salor_printer
      text = @dt.escpos
      render :text => Escper::Asciifier.new.process(text)
    else
      text = @dt.print
      render :nothing => true
    end
    r = Receipt.new
    r.vendor = @current_vendor
    r.company = @current_company
    r.cash_register = @current_register
    r.user = @current_user
    r.drawer = @current_user.get_drawer
    r.content = text
    r.ip = request.ip
    r.save
  end
  
  def report_day
    @from, @to = assign_from_to(params)
    @from = @from ? @from.beginning_of_day : Time.now.beginning_of_day
    @to = @to ? @to.end_of_day : @from.end_of_day
    @users = @current_vendor.users.visible.where(:uses_drawer_id => nil)
    if params[:user_id].blank?
      drawer = nil
    else
      @user = @current_vendor.users.visible.find_by_id(params[:user_id])
      drawer = @user.get_drawer
    end
    @report = @current_vendor.get_end_of_day_report(@from, @to, drawer)
  end


  def render_report_day
    @from, @to = assign_from_to(params)
    @from = @from ? @from.beginning_of_day : Time.now.beginning_of_day
    @to = @to ? @to.end_of_day : @from.end_of_day
    @user = @current_vendor.users.visible.find_by_id(params[:user_id])
    if params[:user_id].blank?
      drawer = nil
    else
      @user = @current_vendor.users.visible.find_by_id(params[:user_id])
      drawer = @user.get_drawer
    end
    if @current_register.salor_printer
      text = @current_vendor.escpos_eod_report(@from, @to, drawer)
      render :text => Escper::Asciifier.new.process(text)
      return
    else
      text = @current_vendor.print_eod_report(@from, @to, drawer, @current_register)
      render :nothing => true
    end
    
    r = Receipt.new
    r.vendor = @current_vendor
    r.company = @current_company
    r.cash_register = @current_register
    r.user = @current_user
    r.drawer = @current_user.get_drawer
    r.content = text
    r.ip = request.ip
    r.save
  end
  
  def edit_field_on_child
    klass = params[:klass].constantize
    @inst = klass.where(:vendor_id => @current_vendor).find_by_id(params[:id])
    
    if @inst.nil?
      raise "edit_field_on_child: @inst is nil. The model with ID #{ params[:id] } probably not existing."
    end
    
    log_action "edit_field_on_child called. @inst.class is #{ @inst.class }"

    value = params[:value]
    if @inst.respond_to?("#{ params[:field] }=".to_sym)
      log_action "edit_field_on_child: sending #{  params[:field] } = #{ value } to #{ @inst.class } id #{ @inst.id }"
      @inst.send("#{ params[:field] }=", value)
      result = @inst.save
      if result != true
        msg = "#{ @inst.class } could not be saved"
        log_action msg
        raise msg
      end
      
    else
      msg = "VendorsController#edit_field_on_child: #{ klass } does not respond well to setter method #{ params[:field] }!"
      log_action msg
      raise msg
    end
    
    if @inst.class == ShipmentItem
      @shipment_item = @inst
      @shipment_item.calculate_totals

      if params[:field] == 'quantity' and params[:value].to_i.zero?
        @shipment_item.hide(@current_user)
      end
      @shipment_items = [@shipment_item]
      @shipment = @shipment_item.shipment
      @shipment.calculate_totals
      render 'shipments/update_pos_display'
      
    elsif @inst.class == OrderItem
      @order_item = @inst
      #README If someone edits the quantity or price of an item, Actions need to be informed of this.
      case params[:field]
      when 'price'
        @order_item = Action.run(@current_vendor, @order_item, :change_price)
      when 'quantity'
        @order_item = Action.run(@current_vendor, @order_item, :change_quantity)
        @order_item = Action.run(@current_vendor, @order_item, :add_to_order) # a change in qty is the same
        # as adding to an order otherwise we have to create 2 actions to accomplish the same thing.
      end

      @order_item.calculate_totals
      @order_item.order.calculate_totals
      
      # set variables for the js.erb view
      @order = @order_item.order
      @order_items = [@order_item]
      if @order_item.behavior == 'gift_card' and @order_item.activated.nil? and @order_item.price_cents > 0
        # this is a dynamically generated gift card item. if this variable is set, the view has to start a print request to print a sticker.
        @gift_card_item_id_for_print = @order_item.item_id
      end
      log_action "Rendering orders/update_pos_display"
      render 'orders/update_pos_display'
      
    elsif @inst.class == Order
      @order = @inst
      @order.calculate_totals
      
      if ['rebate', 'tax_profile_id', 'toggle_buy_order', 'toggle_is_proforma'].include?(params[:field])
        # those order attributes will be passed on to all OrderItems, so we have to update them all in the view.
        @order_items = @order.order_items.visible
      else
        # do not update any order_items
        @order_items = []
      end
      render 'orders/update_pos_display'
      
    else
      log_action "Rendering nothing"
      render :nothing => true
    end
    History.record("edit_field_on_child", @inst)
  end

  def history
    @histories = @current_vendor.histories.order("created_at desc").page(params[:page]).per(@current_vendor.pagination)
  end
  
  def statistics
    f, t = assign_from_to(params)
    params[:limit] ||= 15
    @limit = params[:limit].to_i - 1
    
    @reports = @current_vendor.get_statistics(f, t)
    
    view = SalorRetail::Application::CONFIGURATION[:reports][:style]
    view ||= 'default'
    render "/vendors/reports/#{view}/page"
  end
  
  def export
    if params[:file] then
      manager = CsvManager.new(params[:file],"\t")
      if params[:do_what] == 'download' then
        output = manager.route(params)
        send_csv(output,params[:download_type] + '_Download') and return
      else
        output = manager.send params[:do_what]
        no = output[:successes].join "\n"
        no = no + "\n" + output[:errors].join("\n")
        send_csv(no,params[:do_what]) and return
      end
    end
  end

  def labels
    render :layout => false    
  end
  
  def display_logo
    render :layout => 'customer_display'
  end
  
  def backup
    configpath = SalorRetail::Application::SR_DEBIAN_SITEID == 'none' ? 'config/database.yml' : "/etc/salor-retail/#{SalorRetail::Application::SR_DEBIAN_SITEID}/database.yml"
    dbconfig = YAML::load(File.open(configpath))
    mode = ENV['RAILS_ENV'] ? ENV['RAILS_ENV'] : 'development'
    username = dbconfig[mode]['username']
    password = dbconfig[mode]['password']
    database = dbconfig[mode]['database']
    `mysqldump -u #{username} -p#{password} #{database} | bzip2 -c > #{Rails.root}/tmp/backup-#{$Vendor.id}.sql.bz2`

    send_file("#{Rails.root}/tmp/backup-#{$Vendor.id}.sql.bz2",:type => :bzip,:disposition => "attachment",:filename => "backup-#{$Vendor.id}.sql.bz2")
  end


  private

  def send_csv(lines,name)
    ftype = 'tsv'
    send_data(lines, :filename => "#{name}_#{Time.now.year}#{Time.now.month}#{Time.now.day}-#{Time.now.hour}#{Time.now.min}.#{ftype}", :type => 'application-x/csv') and return
	end
	# {END}
end
