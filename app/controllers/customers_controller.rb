# ------------------- Salor Point of Sale ----------------------- 
# An innovative multi-user, multi-store application for managing
# small to medium sized retail stores.
# Copyright (C) 2011-2012  Jason Martin <jason@jolierouge.net>
# Visit us on the web at http://salorpos.com
# 
# This program is commercial software (All provided plugins, source code, 
# compiled bytecode and configuration files, hereby referred to as the software). 
# You may not in any way modify the software, nor use any part of it in a 
# derivative work.
# 
# You are hereby granted the permission to use this software only on the system 
# (the particular hardware configuration including monitor, server, and all hardware 
# peripherals, hereby referred to as the system) which it was installed upon by a duly 
# appointed representative of Salor, or on the system whose ownership was lawfully 
# transferred to you by a legal owner (a person, company, or legal entity who is licensed 
# to own this system and software as per this license). 
#
# You are hereby granted the permission to interface with this software and
# interact with the user data (Contents of the Database) contained in this software.
#
# You are hereby granted permission to export the user data contained in this software,
# and use that data any way that you see fit.
#
# You are hereby granted the right to resell this software only when all of these conditions are met:
#   1. You have not modified the source code, or compiled code in any way, nor induced, encouraged, 
#      or compensated a third party to modify the source code, or compiled code.
#   2. You have purchased this system from a legal owner.
#   3. You are selling the hardware system and peripherals along with the software. They may not be sold
#      separately under any circumstances.
#   4. You have not copied the software, and maintain no sourcecode backups or copies.
#   5. You did not install, or induce, encourage, or compensate a third party not permitted to install 
#      this software on the device being sold.
#   6. You have obtained written permission from Salor to transfer ownership of the software and system.
#
# YOU MAY NOT, UNDER ANY CIRCUMSTANCES
#   1. Transmit any part of the software via any telecommunications medium to another system.
#   2. Transmit any part of the software via a hardware peripheral, such as, but not limited to,
#      USB Pendrive, or external storage medium, Bluetooth, or SSD device.
#   3. Provide the software, in whole, or in part, to any thrid party unless you are exercising your
#      rights to resell a lawfully purchased system as detailed above.
#
# All other rights are reserved, and may be granted only with direct written permission from Salor. By using
# this software, you agree to adhere to the rights, terms, and stipulations as detailed above in this license, 
# and you further agree to seek to clarify any right not directly spelled out herein. Any right, not directly 
# covered by this license is assumed to be reserved by Salor, and you agree to contact an official Salor repre-
# sentative to clarify any rights that you infer from this license or believe you will need for the proper 
# functioning of your business.
# {VOCABULARY} customer_object customer_info customer_sku customer_loyalty_card customer_pagination customer_undefined
# {VOCABULARY} customer_orders customer_order_items customer_points customer_rebates customer_order_items
class CustomersController < ApplicationController
  # {START}
  before_filter :authify, :except => [:labels]
  before_filter :initialize_instance_variables, :except => [:labels]
  before_filter :check_role, :except => [:labels]
  before_filter :crumble, :except => [:labels]
  # GET /customers
  # GET /customers.xml
  def index
    @customers = Customer.scopied.page(GlobalData.params.page).per(GlobalData.conf.pagination)

    respond_to do |format|
      format.html # index.html.erb
      format.xml  { render :xml => @customers }
    end
  end

  # GET /customers/new
  # GET /customers/new.xml
  def new
    @customer = Customer.new
    @customer.loyalty_card = LoyaltyCard.new
    respond_to do |format|
      format.html # new.html.erb
      format.xml  { render :xml => @customer }
    end
  end

  def show
    @customer = Customer.scopied.find_by_id(params[:id])
    @report = @customer.get_sales_statistics
  end

  # GET /customers/1/edit
  def edit
    @customer = Customer.find(params[:id])
    if not @customer.loyalty_card then
      @customer.loyalty_card = LoyaltyCard.new
    end
    add_breadcrumb I18n.t("menu.customer") + ' ' + @customer.full_name,'edit_customer_path(@customer,:vendor_id => params[:vendor_id])'
  end

  # POST /customers
  # POST /customers.xml
  def create
    
    @customer = Customer.new(params[:customer])
    @loyalty_card = LoyaltyCard.new(params[:loyalty_card])

    respond_to do |format|
      if @loyalty_card.save and @customer.save
        @loyalty_card.update_attribute(:customer_id,@customer.id)
        format.html { redirect_to(:action => 'index', :notice => I18n.t("views.notice.model_create", :model => Customer.model_name.human)) }
        format.xml  { render :xml => @customer, :status => :created, :location => @customer }
      else
        flash[:notice] = I18n.t("system.errors.sku_must_be_unique",:sku => @loyalty_card.sku)
        @customer.loyalty_card = @loyalty_card
        format.html { render :action => "new" }
        format.xml  { render :xml => @customer.errors, :status => :unprocessable_entity }
      end
    end
  end

  # PUT /customers/1
  # PUT /customers/1.xml
  def update
    @customer = Customer.find(params[:id])

    respond_to do |format|
      if @customer.update_attributes(params[:customer])
        @customer.loyalty_card.update_attributes params[:loyalty_card]
        format.html { redirect_to(:action => 'index', :notice => 'Customer was successfully updated.') }
        format.xml  { head :ok }
      else
        format.html { render :action => "edit" }
        format.xml  { render :xml => @customer.errors, :status => :unprocessable_entity }
      end
    end
  end

  # DELETE /customers/1
  # DELETE /customers/1.xml
  def destroy
    @customer = Customer.find(params[:id])
    @customer.loyalty_card.kill 
    @customer.kill

    respond_to do |format|
      format.html { redirect_to(customers_url) }
      format.xml  { head :ok }
    end
  end

  def labels
    if params[:user_type] == 'User'
      @user = User.find_by_id(params[:user_id])
    else
      @user = Employee.find_by_id(params[:user_id])
    end
    @register = CashRegister.find_by_id(params[:cash_register_id])
    @vendor = @register.vendor if @register
    #`espeak -s 50 -v en "#{ params[:cash_register_id] }"`
    render :nothing => true and return if @register.nil? or @vendor.nil? or @user.nil?

    @customers = Customer.find_all_by_id(params[:id])
    text = Printr.new.sane_template(params[:type],binding)
    if @register.salor_printer
      render :text => text
      #`beep -f 2000 -l 10 -r 3`
    else
      printer_path = params[:type] == 'lc_sticker' ? @register.sticker_printer : @register.thermal_printer
      File.open(printer_path,'w:ISO-8859-15') { |f| f.write text }
      render :nothing => true
    end
  end

  def upload_optimalsoft
    if params[:file]
      lines = params[:file].read.split("\n")
      i, updated_items, created_items, created_categories, created_tax_profiles = FileUpload.new.type4(lines)
      redirect_to(:action => 'index')
    else
      redirect_to :controller => 'items', :action => 'upload'
    end
  end

  private 
  def crumble
    @vendor = salor_user.get_vendor(salor_user.meta.vendor_id)
    add_breadcrumb @vendor.name,'vendor_path(@vendor)'
    add_breadcrumb I18n.t("menu.customers"),'customers_path(:vendor_id => params[:vendor_id])'
  end
  # {END}
end
