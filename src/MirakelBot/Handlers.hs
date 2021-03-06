{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE TemplateHaskell            #-}
module MirakelBot.Handlers where

import           Control.Applicative
import           Control.Concurrent
import           Control.Concurrent.MVar
import           Control.Lens
import           Control.Monad.Reader
import           Control.Monad.Trans.Maybe
import qualified Data.Map                  as M
import           Data.Maybe
import           Data.Unique
import           MirakelBot.Internal

runHandler :: HandlerInfo -> Handler a -> IO (Maybe a)
runHandler i = flip runReaderT i . runMaybeT . runHandler'

getMessage :: Handler Message
getMessage = Handler $ view handlerMessage

getBotEnv :: Handler BotEnv
getBotEnv = Handler $ view handlerEnv

getOwnId :: Handler HandlerId
getOwnId = Handler $ view handlerId

getUserList :: Channel -> Handler UserList
getUserList channel = Handler $ do
    mv <- view (handlerEnv.userlist)
    ul <- liftIO $ readMVar mv
    return $ fromMaybe M.empty (M.lookup channel ul)

runIrc :: Irc a -> Handler a
runIrc irc = do
    env <- getBotEnv
    liftIO $ runReaderT irc env

forkHandler :: Handler () -> Handler ThreadId
forkHandler h = Handler $ do
    info <- ask
    liftIO . forkIO . void $ runHandler info h

modifyUserList :: Channel -> (UserList -> UserList) -> Handler ()
modifyUserList channel f = Handler $ do
    ul <- view $ handlerEnv.userlist
    liftIO $ modifyMVar_ ul $ return . M.alter modList channel
    where
        modList Nothing = Just $ f M.empty
        modList (Just a) = Just $ f a

addUser :: Channel -> Nick -> UserMode -> Handler ()
addUser channel user mode = modifyUserList channel $ M.insert user mode

delUser :: Channel -> Nick -> Handler ()
delUser channel user = modifyUserList channel $ M.delete user

getUserMode :: Channel -> Nick -> Handler (Maybe UserMode)
getUserMode channel nick = do
    ul <- getUserList channel
    return $ M.lookup nick ul

userIsOnline :: Channel -> Nick -> Handler Bool
userIsOnline channel nick = isJust <$> getUserMode channel nick


-- | Generates new unique HandelrId
generateHandlerId :: Irc HandlerId
generateHandlerId = HandlerId <$> liftIO newUnique

-- | Add a Handler to the Handler list
registerHandler :: Handler () -> Irc HandlerId
registerHandler h = do
    i <- generateHandlerId
    mvar <- view handlers
    liftIO . modifyMVar_ mvar $ return . ((i,h) :)
    return i

-- | Removes a Handler from the Handler List
unregisterHandler :: HandlerId -> Irc ()
unregisterHandler hid = do
    mvar <- view handlers
    liftIO . modifyMVar_ mvar $ return . filter (\h -> fst h /= hid)

unregisterSelf :: Handler ()
unregisterSelf = do
    i <- getOwnId
    runIrc $ unregisterHandler i

-- |
handleMessage :: Message -> Irc ()
handleMessage msg = do
    env <- ask
    hs <- liftIO . readMVar $ env^.handlers
    liftIO . forM_ hs $ \(hid, h) -> forkIO . void $ runHandler (HandlerInfo msg env hid) h

