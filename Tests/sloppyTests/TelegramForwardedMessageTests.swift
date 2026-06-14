import Foundation
import Testing
@testable import ChannelPluginTelegram

@Test
func telegramForwardOriginUserMessageIsDecodedAndPrefixed() throws {
    let json = #"""
    {
      "update_id": 1,
      "message": {
        "message_id": 10,
        "from": {"id": 100, "first_name": "Sender"},
        "chat": {"id": 200, "type": "private"},
        "date": 1700000000,
        "text": "hello from forwarded user",
        "forward_origin": {
          "type": "user",
          "date": 1699999999,
          "sender_user": {"id": 300, "first_name": "Alice", "last_name": "Smith", "username": "alice"}
        }
      }
    }
    """#.data(using: .utf8)!

    let update = try JSONDecoder().decode(TelegramBotAPI.Update.self, from: json)
    let message = try #require(update.message)

    let forwarded = try #require(TelegramForwardedMessage.from(message))
    #expect(forwarded.attribution == "@alice")
    #expect(forwarded.date == 1699999999)
    #expect(TelegramForwardedMessage.contentForModel(text: "hello from forwarded user", message: message) == "Forwarded message from @alice:\nhello from forwarded user")
}

@Test
func telegramLegacyForwardFieldsAreDecodedAndPrefixed() throws {
    let json = #"""
    {
      "update_id": 2,
      "message": {
        "message_id": 11,
        "from": {"id": 100, "first_name": "Sender"},
        "chat": {"id": 200, "type": "private"},
        "date": 1700000000,
        "text": "legacy forward",
        "forward_from": {"id": 301, "first_name": "Bob", "last_name": "Stone"},
        "forward_date": 1699999998
      }
    }
    """#.data(using: .utf8)!

    let update = try JSONDecoder().decode(TelegramBotAPI.Update.self, from: json)
    let message = try #require(update.message)

    let forwarded = try #require(TelegramForwardedMessage.from(message))
    #expect(forwarded.attribution == "Bob Stone")
    #expect(forwarded.date == 1699999998)
    #expect(TelegramForwardedMessage.contentForModel(text: "legacy forward", message: message) == "Forwarded message from Bob Stone:\nlegacy forward")
}

@Test
func telegramHiddenForwardFallsBackToGenericHeader() throws {
    let json = #"""
    {
      "update_id": 3,
      "message": {
        "message_id": 12,
        "from": {"id": 100, "first_name": "Sender"},
        "chat": {"id": 200, "type": "private"},
        "date": 1700000000,
        "text": "anonymous forward",
        "forward_origin": {
          "type": "hidden_user",
          "date": 1699999997
        }
      }
    }
    """#.data(using: .utf8)!

    let update = try JSONDecoder().decode(TelegramBotAPI.Update.self, from: json)
    let message = try #require(update.message)

    let forwarded = try #require(TelegramForwardedMessage.from(message))
    #expect(forwarded.attribution == nil)
    #expect(TelegramForwardedMessage.contentForModel(text: "anonymous forward", message: message) == "Forwarded message:\nanonymous forward")
}

@Test
func telegramRegularMessageIsNotPrefixed() throws {
    let json = #"""
    {
      "update_id": 4,
      "message": {
        "message_id": 13,
        "from": {"id": 100, "first_name": "Sender"},
        "chat": {"id": 200, "type": "private"},
        "date": 1700000000,
        "text": "regular"
      }
    }
    """#.data(using: .utf8)!

    let update = try JSONDecoder().decode(TelegramBotAPI.Update.self, from: json)
    let message = try #require(update.message)

    #expect(TelegramForwardedMessage.from(message) == nil)
    #expect(TelegramForwardedMessage.contentForModel(text: "regular", message: message) == "regular")
}
