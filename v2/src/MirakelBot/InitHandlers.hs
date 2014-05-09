module MirakelBot.InitHandlers where
import           MirakelBot.Handlers.Id
import           MirakelBot.Handlers.ServerComm
import           MirakelBot.Handlers.Talk
import           MirakelBot.Handlers.Mirakel
import           MirakelBot.Types

miscHandlers :: [Irc ()]
miscHandlers = [MirakelBot.Handlers.Id.init,MirakelBot.Handlers.ServerComm.init,MirakelBot.Handlers.Talk.init,MirakelBot.Handlers.Mirakel.init]
