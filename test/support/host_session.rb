require_relative 'host_source'
require EltenTestHost.file('src/eapi/structs.rb')

# ELTEN exports this host-owned module for app code. Headless UI fixtures do
# not start the host loader; supply the same module without inventing a user
# or replacing a scenario's explicit account/identity double.
Object.const_set(:Session, EltenAPI::Structs::Session) unless Object.const_defined?(:Session, false)
