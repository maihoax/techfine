//+------------------------------------------------------------------+
//|                                              TimeFilter.mqh      |
//|                          Trading Time Filter Management          |
//|              Hour-based and Day-of-week based filtering          |
//+------------------------------------------------------------------+
#property copyright "2025"
#property strict

//+------------------------------------------------------------------+
//| Time Filter Class                                                |
//+------------------------------------------------------------------+
class CTimeFilter
{
private:
   // Hour filtering
   bool              m_useHourFilter;
   int               m_startHour;
   int               m_endHour;

   // Day of week filtering
   bool              m_useDayFilter;
   bool              m_allowMonday;
   bool              m_allowTuesday;
   bool              m_allowWednesday;
   bool              m_allowThursday;
   bool              m_allowFriday;

   // Session-based filtering (for Gold market)
   bool              m_useSessionFilter;
   bool              m_allowAsianSession;
   bool              m_allowEuropeanSession;
   bool              m_allowUSSession;

public:
   //--- Constructor
   CTimeFilter()
   {
      m_useHourFilter = false;
      m_startHour = 0;
      m_endHour = 23;

      m_useDayFilter = false;
      m_allowMonday = true;
      m_allowTuesday = true;
      m_allowWednesday = true;
      m_allowThursday = true;
      m_allowFriday = true;

      m_useSessionFilter = false;
      m_allowAsianSession = true;
      m_allowEuropeanSession = true;
      m_allowUSSession = true;
   }

   //--- Initialize with custom settings
   void Init(bool useHour = false,
             int startHour = 0,
             int endHour = 23,
             bool useDay = false)
   {
      m_useHourFilter = useHour;
      m_startHour = startHour;
      m_endHour = endHour;
      m_useDayFilter = useDay;
   }

   //--- Check if trading is allowed at current time
   bool IsTradeAllowed()
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);

      // Check hour filter
      if(m_useHourFilter)
      {
         if(!IsHourAllowed(dt.hour))
            return false;
      }

      // Check day of week filter
      if(m_useDayFilter)
      {
         if(!IsDayAllowed(dt.day_of_week))
            return false;
      }

      // Check session filter (for Gold)
      if(m_useSessionFilter)
      {
         if(!IsSessionAllowed(dt.hour))
            return false;
      }

      return true;
   }

   //--- Check if specific hour is allowed
   bool IsHourAllowed(int hour)
   {
      if(!m_useHourFilter)
         return true;

      // Handle cases where end hour wraps around midnight
      if(m_startHour <= m_endHour)
      {
         return (hour >= m_startHour && hour <= m_endHour);
      }
      else
      {
         return (hour >= m_startHour || hour <= m_endHour);
      }
   }

   //--- Check if specific day is allowed
   bool IsDayAllowed(int dayOfWeek)
   {
      if(!m_useDayFilter)
         return true;

      // dayOfWeek: 0=Sunday, 1=Monday, 2=Tuesday, etc.
      switch(dayOfWeek)
      {
         case 1: return m_allowMonday;
         case 2: return m_allowTuesday;
         case 3: return m_allowWednesday;
         case 4: return m_allowThursday;
         case 5: return m_allowFriday;
         default: return false; // Weekend
      }
   }

   //--- Check if current session is allowed (Gold market sessions)
   bool IsSessionAllowed(int hour)
   {
      if(!m_useSessionFilter)
         return true;

      // Asian Session: 00:00 - 09:00 GMT
      if(hour >= 0 && hour < 9)
         return m_allowAsianSession;

      // European Session: 09:00 - 17:00 GMT
      if(hour >= 9 && hour < 17)
         return m_allowEuropeanSession;

      // US Session: 17:00 - 24:00 GMT
      if(hour >= 17 && hour < 24)
         return m_allowUSSession;

      return false;
   }

   //--- Get session name for current time
   string GetCurrentSession()
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);

      if(dt.hour >= 0 && dt.hour < 9)
         return "ASIAN";
      else if(dt.hour >= 9 && dt.hour < 17)
         return "EUROPEAN";
      else if(dt.hour >= 17 && dt.hour < 24)
         return "US";

      return "UNKNOWN";
   }

   //--- Get trading status info
   string GetFilterInfo()
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);

      string info = "Time Filter: ";

      if(!m_useHourFilter && !m_useDayFilter && !m_useSessionFilter)
      {
         info += "DISABLED";
         return info;
      }

      info += "\n";

      if(m_useHourFilter)
      {
         info += "Hours: " + IntegerToString(m_startHour) + ":00 - " +
                 IntegerToString(m_endHour) + ":00\n";
         info += "Current Hour: " + IntegerToString(dt.hour) + ":00 ";
         info += (IsHourAllowed(dt.hour) ? "[OK]" : "[BLOCKED]") + "\n";
      }

      if(m_useDayFilter)
      {
         string days[] = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"};
         info += "Day: " + days[dt.day_of_week] + " ";
         info += (IsDayAllowed(dt.day_of_week) ? "[OK]" : "[BLOCKED]") + "\n";
      }

      if(m_useSessionFilter)
      {
         info += "Session: " + GetCurrentSession() + " ";
         info += (IsSessionAllowed(dt.hour) ? "[OK]" : "[BLOCKED]") + "\n";
      }

      return info;
   }

   //--- Setters for hour filter
   void SetHourFilter(bool enable, int startHour = 0, int endHour = 23)
   {
      m_useHourFilter = enable;
      m_startHour = startHour;
      m_endHour = endHour;
   }

   //--- Setters for day filter
   void SetDayFilter(bool enable)
   {
      m_useDayFilter = enable;
   }

   void AllowDay(int dayOfWeek, bool allow)
   {
      switch(dayOfWeek)
      {
         case 1: m_allowMonday = allow; break;
         case 2: m_allowTuesday = allow; break;
         case 3: m_allowWednesday = allow; break;
         case 4: m_allowThursday = allow; break;
         case 5: m_allowFriday = allow; break;
      }
   }

   void SetDaysAllowed(bool mon, bool tue, bool wed, bool thu, bool fri)
   {
      m_allowMonday = mon;
      m_allowTuesday = tue;
      m_allowWednesday = wed;
      m_allowThursday = thu;
      m_allowFriday = fri;
   }

   //--- Setters for session filter (Gold market)
   void SetSessionFilter(bool enable)
   {
      m_useSessionFilter = enable;
   }

   void SetSessionsAllowed(bool asian, bool european, bool us)
   {
      m_allowAsianSession = asian;
      m_allowEuropeanSession = european;
      m_allowUSSession = us;
   }

   //--- Getters
   bool IsHourFilterEnabled() { return m_useHourFilter; }
   bool IsDayFilterEnabled() { return m_useDayFilter; }
   bool IsSessionFilterEnabled() { return m_useSessionFilter; }
   int GetStartHour() { return m_startHour; }
   int GetEndHour() { return m_endHour; }
};
