{-# OPTIONS_GHC -fno-warn-orphans #-}
module Tests.Network.Socket.WaitSpec where
import qualified Network.Socket.Wait.Internal as W
import qualified Network.Socket.Free as F
import qualified Network.Socket as N
import qualified Control.Concurrent as C
import qualified Control.Concurrent.STM as S
import qualified Control.Exception as E
import qualified Test.Hspec as H
import qualified System.Timeout as T
import qualified Control.Concurrent.Async as A
import qualified Control.Monad.Trans.State as St

instance Monad m => Semigroup (St.StateT s m ()) where
  (<>) = (>>)

instance Monad m => Monoid (St.StateT s m ()) where
  mempty = pure ()
  mappend = (<>)

main :: IO ()
main = H.hspec spec

throwTimeout :: Int -> String -> IO a -> IO a
throwTimeout delay msg action = T.timeout delay action >>= \case
  Nothing -> fail $ "timed out " ++ msg
  Just x -> pure x

spec :: H.Spec
spec = do
  H.describe "connectAction" $ H.before F.openFreePort $ H.after (N.close . snd) $ do
    H.it "returns False if it fails to connect" $ \(port, sock) -> do
      N.close sock
      -- There is a small race that another process might bind to this port
      W.connectAction "127.0.0.1" port `H.shouldReturn` False

    H.it "returns True if it connects" $ \(port, sock) -> do
      N.listen sock 128

      W.connectAction "127.0.0.1" port `H.shouldReturn` True

    H.it "returns True if connects after failing" $ \(port, sock) -> do
      N.close sock

      W.connectAction "127.0.0.1" port `H.shouldReturn` False

      E.bracket (N.socket N.AF_INET N.Stream N.defaultProtocol) N.close $ \sock' -> do
         N.bind sock' $ N.SockAddrInet (fromIntegral port) $ N.tupleToHostAddress (127,0,0,1)
         N.listen sock' 128

         W.connectAction "127.0.0.1" port `H.shouldReturn` True

    H.it "throws if the host does not exist" $ \(_, _) -> do
      W.connectAction "invalid." 3000 `H.shouldThrow` (\(_ :: IOError) -> True)

  H.describe "waitM" $ do
    H.it "returns immediantly if the action returns True" $
      flip St.execState False (W.waitM mempty (St.put True) (pure True)) `H.shouldBe` False

    H.it "loops until the action returns True" $ do
      let theAction = do
            St.get >>= \case
              0 -> St.put 1 >> pure False
              _ -> St.put 2 >> pure True

      flip St.execState 0 (W.waitM mempty (pure ()) theAction) `H.shouldBe` 2
