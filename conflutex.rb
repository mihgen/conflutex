#!/usr/bin/env ruby

require 'rubygems'
require 'sinatra'
require 'helper.rb'
  
get '/convert/pavt/:pageid' do
  create_pdf("pavt", params[:pageid])
end
