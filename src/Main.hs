module Main where 
import           Bot.Bot
import           Bot.Types
import Util.Irc
import           System.Exit
import           Control.Monad.Reader
import           Control.Monad.State
import           Network
import           Control.Arrow
import           Data.List
import           System.Time
import          Options.Applicative
import Data.Monoid
import Data.Foldable (traverse_)

myHandlers :: [BotHandler]
myHandlers =[
         MessageHandler (HotwordPrefix "quit")     quit           "Force Bot to quit the channel"
       , MessageHandler (HotwordInfix "irakel")    handleMention  "Handle mentioning Mirakel"
       , MessageHandler (HotwordPrefix "id")       answerId       "Print parameter"
       , MessageHandler (HotwordPrefix "uptime")   answerUptime   "Print bot uptime"
       , MessageHandler (HotwordPrefix "users")    answerUsers    "Print online users"
       , MessageHandler (HotwordPrefix "help")     showHelp       "Print help message"
    ]

main :: IO ()
main = do
    -- Parse
    cfg <- execParser opts
    runBot cfg

    where
        opts = info (helper <*> parser) mempty
        parser = BotConfig
                    <$> strOption
                        ( short 's'
                       <> long "server"
                       <> metavar "SERVER"
                       <> help "IRC Server where I should connect to" )
                    <*> (PortNumber . fromIntegral <$> option
                        ( short 'p'
                       <> long "port"
                       <> metavar "PORT"
                       <> value (6667 :: Int) -- To avoid "Defaulting the following constraint(s) to type ‘Integer’"
                       <> help "Port" ))
                    <*> strOption
                        ( short 'c'
                       <> long "chan"
                       <> metavar "CHANNEL"
                       <> help "Channel" )
                    <*> strOption
                        ( short 'n'
                       <> long "nick"
                       <> metavar "NICK"
                       <> help "Nick name" )
                    <*> strOption
                        ( long "hotword"
                       <> metavar "HOTWORD"
                       <> help "The prefix hotword" )
                    <*> many (strOption
                        ( short 'm'
                       <> long "masters"
                       <> metavar "MASTERS"
                       <> help "List of master users" ))
                    <*> pure myHandlers

quit :: Hook
quit TextMsg { msgSender = sender}  _ = do
    masters <- asks $ botMasters . botConfig
    if (userName sender) `elem` masters
    then
        writeRaw "QUIT" [":Exiting"] >> liftIO (exitWith ExitSuccess)
    else
        answer "You are not my master!"

handleMention :: Hook
handleMention TextMsg { msgSender = sender} _ = do
    answer $ unwords ["Hello", userName sender,"please tell me what you want to know"]

getWord :: Hotword -> String
getWord (HotwordPrefix x) = x
getWord (HotwordInfix x) = x

answerId :: Hook
answerId TextMsg { msgMessage = msg} hot = do
    prefixHotword <- asks $ botHotword . botConfig
    answer $ text prefixHotword msg
    where
        text :: String -> String -> String
        text p message = snd $ splitAt ((length p) + (length $ getWord hot)) message

answerUptime :: Hook
answerUptime _ _ = do
    now <- liftIO getClockTime
    zero <- asks starttime
    answer $ prettyTimeDiff $ diffClockTimes now zero

prettyTimeDiff :: TimeDiff -> String
prettyTimeDiff td =
    unwords $ map ( uncurry (++) . first show) $
        if null diffs then [(0,"s")] else diffs
        where merge (tot,acc) (sec,typ) = let (sec',tot') = divMod tot sec
                                        in (tot', (sec',typ):acc)
              metrics = [(86400,"d"),(3600,"h"),(60,"m"),(1,"s")]
              diffs = filter ((/=0) . fst) $ reverse $snd $
                        foldl' merge (tdSec td, []) metrics

answerUsers :: Hook
answerUsers _ _ = do
    users <- gets onlineUsers
    writeRaw "NAMES" ["#mirakelbot"]
    answer $ show $ map userName users

showHelp :: Hook
showHelp _ _ = do
    prefixHotword <- asks $ botHotword . botConfig
    let helps= map (showHandlerHelp prefixHotword)  myHandlers
    answer "I am the MirakelBot. You can chat with me here or in a private chat. You can use following commands:"
    traverse_ answer helps
    where
        showHandlerHelp prefixHotword MessageHandler {handlerHotword = hot, handlerHelp = helpMessage} = 
            unwords [showHotword prefixHotword $ hot, ":" , helpMessage]
        showHandlerHelp _ _ = ""

        showHotword :: String -> Hotword -> String
        showHotword hot (HotwordPrefix a) = hot ++ a
        showHotword _ (HotwordInfix a) = unwords ["infix", a]
