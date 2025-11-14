//+------------------------------------------------------------------+
//|                                            TelegramBot.mqh       |
//|                      Enhanced Telegram Bot Integration          |
//|                  Remote Control and Notifications for EA         |
//+------------------------------------------------------------------+
#property copyright "2025"
#property strict

//+------------------------------------------------------------------+
//| Telegram Bot Class                                               |
//+------------------------------------------------------------------+
class CTelegramBot
{
private:
   string            m_token;
   long              m_chatID;
   int               m_lastUpdateID;
   bool              m_enabled;
   int               m_timeout;

   // Command callbacks
   bool              m_commandReceived;
   string            m_lastCommand;

public:
   //--- Constructor
   CTelegramBot()
   {
      m_token = "";
      m_chatID = 0;
      m_lastUpdateID = 0;
      m_enabled = false;
      m_timeout = 5000;
      m_commandReceived = false;
      m_lastCommand = "";
   }

   //--- Initialize
   bool Init(string token, long chatID)
   {
      m_token = token;
      m_chatID = chatID;

      if(m_token == "" || m_chatID == 0)
      {
         m_enabled = false;
         return false;
      }

      m_enabled = true;
      return true;
   }

   //--- Send message to Telegram
   bool SendMessage(string message)
   {
      if(!m_enabled)
         return false;

      string url = "https://api.telegram.org/bot" + m_token +
                   "/sendMessage?chat_id=" + IntegerToString(m_chatID) +
                   "&text=" + UrlEncode(message) +
                   "&parse_mode=Markdown";

      char result[];
      string headers;

      int res = WebRequest("GET", url, "", m_timeout, result, headers);

      if(res == -1)
      {
         Print("Telegram SendMessage error: ", GetLastError());
         return false;
      }

      return true;
   }

   //--- Send formatted message with line breaks
   bool SendFormattedMessage(string title, string message)
   {
      string fullMessage = "*" + title + "*\n\n" + message;
      return SendMessage(fullMessage);
   }

   //--- Check for new commands
   bool CheckCommands()
   {
      if(!m_enabled)
         return false;

      string url = "https://api.telegram.org/bot" + m_token +
                   "/getUpdates?offset=" + IntegerToString(m_lastUpdateID + 1) +
                   "&timeout=0";

      char result[];
      string headers;

      int res = WebRequest("GET", url, "", m_timeout, result, headers);

      if(res <= 0)
         return false;

      string json = CharArrayToString(result);

      // Parse update_id
      int pos = StringFind(json, "\"update_id\":");
      if(pos >= 0)
      {
         int idStart = pos + 12;
         int idEnd = StringFind(json, ",", idStart);
         if(idEnd < 0)
            idEnd = StringFind(json, "}", idStart);

         string idStr = StringSubstr(json, idStart, idEnd - idStart);
         m_lastUpdateID = (int)StringToInteger(idStr);
      }

      // Parse text command
      pos = StringFind(json, "\"text\":\"");
      if(pos >= 0)
      {
         int textStart = pos + 8;
         int textEnd = StringFind(json, "\"", textStart);

         m_lastCommand = StringSubstr(json, textStart, textEnd - textStart);
         m_commandReceived = true;

         return true;
      }

      return false;
   }

   //--- Get last command received
   string GetLastCommand()
   {
      string cmd = m_lastCommand;
      m_lastCommand = "";
      m_commandReceived = false;
      return cmd;
   }

   //--- Check if command was received
   bool HasCommand()
   {
      return m_commandReceived;
   }

   //--- Send account status
   bool SendAccountStatus()
   {
      string msg = "💰 *Account Status*\n\n";
      msg += "Balance: $" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "\n";
      msg += "Equity: $" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) + "\n";
      msg += "Free Margin: $" + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE), 2) + "\n";
      msg += "Profit: $" + DoubleToString(AccountInfoDouble(ACCOUNT_PROFIT), 2) + "\n";
      msg += "\n";
      msg += "Leverage: 1:" + IntegerToString(AccountInfoInteger(ACCOUNT_LEVERAGE)) + "\n";

      return SendMessage(msg);
   }

   //--- Send position info
   bool SendPositionsInfo()
   {
      int total = PositionsTotal();

      if(total == 0)
      {
         return SendMessage("ℹ️ No open positions");
      }

      string msg = "📊 *Open Positions: " + IntegerToString(total) + "*\n\n";

      for(int i = 0; i < total; i++)
      {
         if(PositionSelectByIndex(i))
         {
            string symbol = PositionGetString(POSITION_SYMBOL);
            long type = PositionGetInteger(POSITION_TYPE);
            double volume = PositionGetDouble(POSITION_VOLUME);
            double profit = PositionGetDouble(POSITION_PROFIT);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);

            string typeStr = (type == POSITION_TYPE_BUY) ? "BUY" : "SELL";

            msg += IntegerToString(i + 1) + ". " + symbol + " " + typeStr + " " +
                   DoubleToString(volume, 2) + " lots\n";
            msg += "   Entry: " + DoubleToString(openPrice, 5) + "\n";
            msg += "   Current: " + DoubleToString(currentPrice, 5) + "\n";
            msg += "   Profit: $" + DoubleToString(profit, 2) + "\n\n";
         }
      }

      return SendMessage(msg);
   }

   //--- Send trading signal notification
   bool SendSignalNotification(string signal, double strength)
   {
      string emoji = "⚠️";
      if(signal == "BUY")
         emoji = "🟢";
      else if(signal == "SELL")
         emoji = "🔴";

      string msg = emoji + " *Trading Signal*\n\n";
      msg += "Direction: " + signal + "\n";
      msg += "Strength: " + DoubleToString(strength, 1) + "%\n";

      return SendMessage(msg);
   }

   //--- Send trade notification
   bool SendTradeNotification(string action, string symbol, string type,
                               double lots, double price)
   {
      string emoji = (type == "BUY") ? "🟢" : "🔴";

      string msg = emoji + " *Trade " + action + "*\n\n";
      msg += "Symbol: " + symbol + "\n";
      msg += "Type: " + type + "\n";
      msg += "Volume: " + DoubleToString(lots, 2) + " lots\n";
      msg += "Price: " + DoubleToString(price, 5) + "\n";

      return SendMessage(msg);
   }

   //--- Send alert notification
   bool SendAlert(string title, string message)
   {
      string msg = "⚠️ *" + title + "*\n\n" + message;
      return SendMessage(msg);
   }

   //--- URL encode helper
   string UrlEncode(string text)
   {
      string result = text;

      StringReplace(result, " ", "%20");
      StringReplace(result, "\n", "%0A");
      StringReplace(result, "*", "%2A");
      StringReplace(result, "_", "%5F");
      StringReplace(result, "[", "%5B");
      StringReplace(result, "]", "%5D");
      StringReplace(result, "(", "%28");
      StringReplace(result, ")", "%29");
      StringReplace(result, "~", "%7E");
      StringReplace(result, "`", "%60");
      StringReplace(result, ">", "%3E");
      StringReplace(result, "#", "%23");
      StringReplace(result, "+", "%2B");
      StringReplace(result, "-", "%2D");
      StringReplace(result, "=", "%3D");
      StringReplace(result, "|", "%7C");
      StringReplace(result, "{", "%7B");
      StringReplace(result, "}", "%7D");
      StringReplace(result, ".", "%2E");
      StringReplace(result, "!", "%21");

      return result;
   }

   //--- Getters
   bool IsEnabled() { return m_enabled; }
   string GetToken() { return m_token; }
   long GetChatID() { return m_chatID; }

   //--- Setters
   void SetTimeout(int timeout) { m_timeout = timeout; }
};
