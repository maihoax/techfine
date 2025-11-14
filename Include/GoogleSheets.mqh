//+------------------------------------------------------------------+
//|                                          GoogleSheets.mqh        |
//|                      Google Sheets Integration Module           |
//|         Track trading statistics and verify MT5 account ID      |
//+------------------------------------------------------------------+
#property copyright "2025"
#property strict

//+------------------------------------------------------------------+
//| Google Sheets Integration Class                                  |
//+------------------------------------------------------------------+
class CGoogleSheets
{
private:
   string            m_scriptURL;        // Google Apps Script Web App URL
   bool              m_enabled;
   long              m_accountID;
   string            m_accountName;
   int               m_updateInterval;   // Seconds between updates
   datetime          m_lastUpdate;

public:
   //--- Constructor
   CGoogleSheets()
   {
      m_scriptURL = "";
      m_enabled = false;
      m_accountID = 0;
      m_accountName = "";
      m_updateInterval = 300; // 5 minutes default
      m_lastUpdate = 0;
   }

   //--- Initialize with Google Apps Script URL
   bool Init(string scriptURL, int updateInterval = 300)
   {
      m_scriptURL = scriptURL;
      m_updateInterval = updateInterval;

      if(m_scriptURL == "")
      {
         m_enabled = false;
         return false;
      }

      // Get MT5 account info
      m_accountID = AccountInfoInteger(ACCOUNT_LOGIN);
      m_accountName = AccountInfoString(ACCOUNT_NAME);

      // Verify account ID with Google Sheets
      if(VerifyAccount())
      {
         m_enabled = true;
         Print("Google Sheets: Account verified - ID: ", m_accountID);
         return true;
      }
      else
      {
         m_enabled = false;
         Print("Google Sheets: Account verification failed");
         return false;
      }
   }

   //--- Verify MT5 account ID with Google Sheets
   bool VerifyAccount()
   {
      if(m_scriptURL == "")
         return false;

      string url = m_scriptURL + "?action=verify" +
                   "&account_id=" + IntegerToString(m_accountID) +
                   "&account_name=" + UrlEncode(m_accountName);

      char result[];
      string headers;
      int timeout = 10000;

      int res = WebRequest("GET", url, "", timeout, result, headers);

      if(res <= 0)
      {
         Print("Google Sheets verification request failed: ", GetLastError());
         return false;
      }

      string response = CharArrayToString(result);

      // Check if response contains "verified":true
      if(StringFind(response, "\"verified\":true") >= 0 ||
         StringFind(response, "verified") >= 0)
      {
         return true;
      }

      return false;
   }

   //--- Send trading statistics to Google Sheets
   bool UpdateStatistics(double balance, double equity, double profit,
                         int openPositions, double drawdown)
   {
      if(!m_enabled)
         return false;

      // Check if enough time has passed since last update
      if(TimeCurrent() - m_lastUpdate < m_updateInterval)
         return true; // Skip update

      string url = m_scriptURL + "?action=update" +
                   "&account_id=" + IntegerToString(m_accountID) +
                   "&balance=" + DoubleToString(balance, 2) +
                   "&equity=" + DoubleToString(equity, 2) +
                   "&profit=" + DoubleToString(profit, 2) +
                   "&positions=" + IntegerToString(openPositions) +
                   "&drawdown=" + DoubleToString(drawdown, 2) +
                   "&timestamp=" + IntegerToString(TimeCurrent());

      char result[];
      string headers;
      int timeout = 10000;

      int res = WebRequest("GET", url, "", timeout, result, headers);

      if(res <= 0)
      {
         Print("Google Sheets update request failed: ", GetLastError());
         return false;
      }

      m_lastUpdate = TimeCurrent();
      return true;
   }

   //--- Log trade to Google Sheets
   bool LogTrade(string action, string symbol, string type,
                 double lots, double openPrice, double sl, double tp)
   {
      if(!m_enabled)
         return false;

      string url = m_scriptURL + "?action=trade" +
                   "&account_id=" + IntegerToString(m_accountID) +
                   "&trade_action=" + action +
                   "&symbol=" + symbol +
                   "&type=" + type +
                   "&lots=" + DoubleToString(lots, 2) +
                   "&price=" + DoubleToString(openPrice, 5) +
                   "&sl=" + DoubleToString(sl, 5) +
                   "&tp=" + DoubleToString(tp, 5) +
                   "&timestamp=" + IntegerToString(TimeCurrent());

      char result[];
      string headers;
      int timeout = 10000;

      int res = WebRequest("GET", url, "", timeout, result, headers);

      if(res <= 0)
      {
         Print("Google Sheets trade log request failed: ", GetLastError());
         return false;
      }

      return true;
   }

   //--- Log event to Google Sheets
   bool LogEvent(string eventType, string message)
   {
      if(!m_enabled)
         return false;

      string url = m_scriptURL + "?action=event" +
                   "&account_id=" + IntegerToString(m_accountID) +
                   "&event_type=" + eventType +
                   "&message=" + UrlEncode(message) +
                   "&timestamp=" + IntegerToString(TimeCurrent());

      char result[];
      string headers;
      int timeout = 10000;

      int res = WebRequest("GET", url, "", timeout, result, headers);

      if(res <= 0)
      {
         Print("Google Sheets event log request failed: ", GetLastError());
         return false;
      }

      return true;
   }

   //--- Send daily summary to Google Sheets
   bool SendDailySummary(double startBalance, double endBalance,
                         double totalProfit, int totalTrades,
                         int winTrades, int lossTrades)
   {
      if(!m_enabled)
         return false;

      double winRate = (totalTrades > 0) ? (double)winTrades / totalTrades * 100.0 : 0.0;

      string url = m_scriptURL + "?action=summary" +
                   "&account_id=" + IntegerToString(m_accountID) +
                   "&start_balance=" + DoubleToString(startBalance, 2) +
                   "&end_balance=" + DoubleToString(endBalance, 2) +
                   "&profit=" + DoubleToString(totalProfit, 2) +
                   "&trades=" + IntegerToString(totalTrades) +
                   "&wins=" + IntegerToString(winTrades) +
                   "&losses=" + IntegerToString(lossTrades) +
                   "&win_rate=" + DoubleToString(winRate, 2) +
                   "&date=" + TimeToString(TimeCurrent(), TIME_DATE);

      char result[];
      string headers;
      int timeout = 10000;

      int res = WebRequest("GET", url, "", timeout, result, headers);

      if(res <= 0)
      {
         Print("Google Sheets summary request failed: ", GetLastError());
         return false;
      }

      return true;
   }

   //--- URL encode helper
   string UrlEncode(string text)
   {
      string result = text;

      StringReplace(result, " ", "%20");
      StringReplace(result, ":", "%3A");
      StringReplace(result, "/", "%2F");
      StringReplace(result, "?", "%3F");
      StringReplace(result, "#", "%23");
      StringReplace(result, "&", "%26");
      StringReplace(result, "=", "%3D");
      StringReplace(result, "+", "%2B");
      StringReplace(result, "$", "%24");
      StringReplace(result, ",", "%2C");
      StringReplace(result, "@", "%40");

      return result;
   }

   //--- Getters
   bool IsEnabled() { return m_enabled; }
   long GetAccountID() { return m_accountID; }
   string GetAccountName() { return m_accountName; }

   //--- Setters
   void SetUpdateInterval(int seconds) { m_updateInterval = seconds; }
   void Enable(bool enable) { m_enabled = enable; }
};

/*
=============================================================================
GOOGLE APPS SCRIPT TEMPLATE FOR GOOGLE SHEETS
=============================================================================

Deploy this as a Web App in Google Apps Script and use the URL in the EA.

function doGet(e) {
  var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName("TradingLog");
  if (!sheet) {
    sheet = SpreadsheetApp.getActiveSpreadsheet().insertSheet("TradingLog");
    sheet.appendRow(["Timestamp", "Account ID", "Action", "Symbol", "Type",
                     "Lots", "Price", "SL", "TP", "Balance", "Equity",
                     "Profit", "Positions", "Drawdown", "Message"]);
  }

  var action = e.parameter.action;
  var accountID = e.parameter.account_id;

  if (action == "verify") {
    // Verify account ID - add your verification logic here
    return ContentService.createTextOutput(JSON.stringify({verified: true}))
                         .setMimeType(ContentService.MimeType.JSON);
  }

  if (action == "update") {
    var timestamp = new Date(e.parameter.timestamp * 1000);
    sheet.appendRow([
      timestamp,
      accountID,
      "UPDATE",
      "",
      "",
      "",
      "",
      "",
      "",
      e.parameter.balance,
      e.parameter.equity,
      e.parameter.profit,
      e.parameter.positions,
      e.parameter.drawdown,
      "Statistics Update"
    ]);
    return ContentService.createTextOutput(JSON.stringify({success: true}))
                         .setMimeType(ContentService.MimeType.JSON);
  }

  if (action == "trade") {
    var timestamp = new Date(e.parameter.timestamp * 1000);
    sheet.appendRow([
      timestamp,
      accountID,
      e.parameter.trade_action,
      e.parameter.symbol,
      e.parameter.type,
      e.parameter.lots,
      e.parameter.price,
      e.parameter.sl,
      e.parameter.tp,
      "",
      "",
      "",
      "",
      "",
      "Trade: " + e.parameter.trade_action
    ]);
    return ContentService.createTextOutput(JSON.stringify({success: true}))
                         .setMimeType(ContentService.MimeType.JSON);
  }

  if (action == "event") {
    var timestamp = new Date(e.parameter.timestamp * 1000);
    sheet.appendRow([
      timestamp,
      accountID,
      "EVENT",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      e.parameter.event_type + ": " + e.parameter.message
    ]);
    return ContentService.createTextOutput(JSON.stringify({success: true}))
                         .setMimeType(ContentService.MimeType.JSON);
  }

  return ContentService.createTextOutput(JSON.stringify({success: false}))
                       .setMimeType(ContentService.MimeType.JSON);
}

=============================================================================
*/
