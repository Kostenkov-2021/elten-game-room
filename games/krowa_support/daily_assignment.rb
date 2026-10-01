# encoding: UTF-8
require "base64"
require "date"
require "digest"
require "json"
require "openssl"
require_relative "normalizer"

module GameRoomKrowa
  # Conceals answers in ordinary table data, not from modified clients: the
  # application necessarily contains the key. The first server record fixes
  # the answer, independently of subsequent dictionary changes.
  module DailyAssignment
    VERSION = 1
    KEY = Digest::SHA256.digest("Power Games|Krowa daily assignment|c24d98cc-9ccd-4d50-b801-459da324ff60|v1").freeze
    module_function

    def word_id(word)
      Digest::SHA256.hexdigest("krowa-word-v1|#{Normalizer.call(word)}")
    end

    def seal(day, word)
      date = normalized_day(day)
      word = Normalizer.call(word)
      validate_word(word)
      cipher = OpenSSL::Cipher.new("aes-256-gcm").encrypt
      cipher.key = KEY
      iv = cipher.random_iv
      cipher.auth_data = date
      encrypted = cipher.update(JSON.generate([VERSION, word_id(word), word])) + cipher.final
      Base64.strict_encode64(iv + cipher.auth_tag + encrypted)
    end

    def open(day, envelope)
      date = normalized_day(day)
      raise ArgumentError, "Invalid daily assignment size" unless envelope.is_a?(String) && envelope.bytesize.between?(40, 512)
      data = Base64.strict_decode64(envelope)
      raise ArgumentError, "Invalid daily assignment" unless data.bytesize > 28
      cipher = OpenSSL::Cipher.new("aes-256-gcm").decrypt
      cipher.key = KEY
      cipher.iv = data.byteslice(0, 12)
      cipher.auth_tag = data.byteslice(12, 16)
      cipher.auth_data = date
      version, identity, word = JSON.parse(cipher.update(data.byteslice(28..)) + cipher.final)
      validate_word(word)
      raise ArgumentError, "Invalid daily assignment identity" unless version == VERSION && identity == word_id(word)
      word
    rescue OpenSSL::Cipher::CipherError, JSON::ParserError
      raise ArgumentError, "Invalid daily assignment"
    end

    def normalized_day(value)
      raise ArgumentError, "Invalid daily date" unless /\A\d{4}-\d{2}-\d{2}\z/.match?(value.to_s)
      Date.iso8601(value.to_s).iso8601
    end

    def validate_word(word)
      raise ArgumentError, "Invalid daily word" unless word.is_a?(String) &&
        word.length.between?(3, 9) && /\A[a-ząćęłńóśźż]+\z/.match?(word)
    end
  end
end
