{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}

module Snap.Snaplet.Internal.Lensed where

import Control.Applicative
import Control.Monad
import Control.Monad.Trans
import Data.Lens.Strict
import Data.Functor
import Control.Monad.CatchIO
import Control.Monad.Reader.Class
import Control.Monad.State.Class
import Control.Monad.State.Strict
import Control.Category
import Prelude hiding (id, (.))
import Snap.Types

newtype Lensed b v m a = Lensed  
  { unlensed :: Lens b v -> v -> b -> m (a, v, b) }

instance Functor m => Functor (Lensed b v m) where
  fmap f (Lensed g) = Lensed $ \l v s ->
    (\(a,v',s') -> (f a, v', s')) <$> g l v s

instance (Functor m, Monad m) => Applicative (Lensed b v m) where
  pure a = Lensed $ \_ v s -> return (a, v, s)
  Lensed mf <*> Lensed ma = Lensed $ \l v s -> do
    (f, v', s') <- mf l v s
    (\(a,v'',s'') -> (f a, v'', s'')) <$> ma l v' s'

instance Monad m => Monad (Lensed b v m) where
  return a = Lensed $ \_ v s -> return (a, v, s)
  Lensed g >>= k = Lensed $ \l v s -> do
    (a, v', s') <- g l v s
    unlensed (k a) l v' s'

instance Monad m => MonadState v (Lensed b v m) where
  get = Lensed $ \_ v s -> return (v, v, s)
  put v' = Lensed $ \_ _ s -> return ((), v', s)

instance Monad m => MonadReader (Lens b v) (Lensed b v m) where
  ask = Lensed $ \l v s -> return (l, v, s)
  local f g = do
    l' <- asks f
    withGlobal l' g

instance MonadTrans (Lensed b v) where
  lift m = Lensed $ \_ v b -> do
      res <- m
      return (res, v, b)

instance MonadIO m => MonadIO (Lensed b v m) where
  liftIO = lift . liftIO

instance MonadPlus m => MonadPlus (Lensed b v m) where
  mzero = lift mzero
  m `mplus` n = Lensed $ \l v b ->
      unlensed m l v b `mplus` unlensed n l v b

withGlobal :: Monad m => Lens b v' -> Lensed b v' m a -> Lensed b v m a 
withGlobal l m = globally $ runLensed m l

with :: Monad m => Lens v v' -> Lensed b v' m a -> Lensed b v m a
with l g = do
  l' <- asks (l .)
  withGlobal l' g

embed :: Monad m => Lens v v' -> Lensed v v' m a -> Lensed b v m a
embed l m = locally $ runLensed m l 

globally :: Monad m => StateT b m a -> Lensed b v m a
globally (StateT f) = Lensed $ \l v s -> liftM (\(a, s') -> (a, l ^$ s', s')) $ f (l ^= v $ s)

locally :: Monad m => StateT v m a -> Lensed b v m a
locally (StateT f) = Lensed $ \_ v s -> liftM (\(a, v') -> (a, v', s)) $ f v

runLensed :: Monad m => Lensed b v m a -> Lens b v -> StateT b m a
runLensed (Lensed f) l = StateT $ \s -> do
  (a, v', s') <- f l (l ^$ s) s
  return (a, l ^= v' $ s')