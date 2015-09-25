module Test.RBM(perf
               ,test
               ) where

--local
import Data.RBM
import qualified Data.Matrix as M

import Data.Matrix((-^))

--utils
import qualified System.Random as R
import Control.Monad.Identity(runIdentity)
import qualified Control.Monad.Trans.State.Strict as S

--benchmark modules
import Criterion.Main(defaultMainWith,defaultConfig,bgroup,bench,whnf)
import Criterion.Types(reportFile,timeLimit)

--test modules
import System.Exit (exitFailure)
import Test.QuickCheck(verboseCheckWithResult)
import Test.QuickCheck.Test(isSuccess,stdArgs,maxSuccess,maxSize)
import Data.Word(Word8)
import Control.Monad.Loops(iterateUntil)

seeds :: Int -> [Int] 
seeds seed = R.randoms (R.mkStdGen seed)

sigmoid :: Double -> Double
sigmoid d = 1 / (1 + (exp (negate d)))

-- |test to see if we can learn a random string
prop_learn :: Word8 -> Word8 -> Word8 -> Bool
prop_learn bs ni nh = runIdentity $ do
   let rbm = newRBM s1 (fi ni) (fi nh)
       (s1:s2:s3:_) = seeds $ (fi ni) * (fi nh) * (fi bs)
       fi ww = 1 + (fromIntegral ww)
       roundD = fromIntegral . (round :: Double -> Int)
   inputs <- M.d2u $ M.map roundD $ M.randomish (fi ni, fi nh) (0, 1) s2
   let script = iterateUntil (0.05>) (contraDivS 0.001 inputs)
   (lrb,_) <- snd <$> S.runStateT script (rbm,s3) 
   recon <- reconstruct lrb inputs
   err <- M.mse (inputs -^ recon)
   return $ (err < 0.1)

-- |test to see if we fail to rearn with a negative learning rate
prop_not_learn :: Word8 -> Word8 -> Word8 -> Bool
prop_not_learn bs ni nh = runIdentity $ do
   let rbm = newRBM s1 (fi ni) (fi nh) 
       fi ww = 1 + (fromIntegral ww)
       (s1:s2:s3:_) = seeds $ (fi ni) * (fi nh) * (fi bs)
       roundD = fromIntegral . (round :: Double -> Int)
   inputs <- M.d2u $ M.map roundD $ M.randomish (fi ni, fi nh) (0, 1) s2
   let script = iterateUntil (0.95<) (contraDivS 0.001 inputs)
   (lrb,_) <- snd <$> S.runStateT script (rbm,s3) 
   recon <- reconstruct lrb inputs
   err <- M.mse (inputs -^ recon)
   return $ (err > 0.9)

prop_init :: Word8 -> Word8 -> Bool
prop_init ni nh = (fi ni) * (fi nh)  == (M.elems rb)
   where
      seed = (fi ni) * (fi nh)
      rb = newRBM seed (fi ni) (fi nh)
      fi :: Word8 -> Int
      fi ww = 1 + (fromIntegral ww)

prop_hiddenProbs :: Word8 -> Word8 -> Bool
prop_hiddenProbs ni nh = runIdentity $ do
   let rb = newRBM seed (fi ni) (fi nh)
       fi ww = 1 + (fromIntegral ww)
       input = M.randomish (1, (fi ni)) (0,1) seed
       seed = (fi ni) * (fi nh)
   pp <- hiddenPs rb input
   return $ (fi nh) == (M.col pp)

prop_hiddenProbs2 :: Bool
prop_hiddenProbs2 = runIdentity $ do
   let h0 = w00 * i0 + w10 * i1
       h1 = w01 * i0 + w11 * i1
       h2 = w02 * i0 + w12 * i1
       i0:i1:_ = [1..]
       w00:w01:w02:w10:w11:w12:_ = [1..]
       wws = [w00,w01,w02,w10,w11,w12]
       input = M.fromList (1,2) $ [i0,i1]
       rb = M.fromList (2,3) wws
   pp <- M.toList <$> hiddenPs rb input
   return $ pp == map sigmoid [h0, h1, h2]

prop_inputProbs :: Word8 -> Word8 -> Bool
prop_inputProbs ni nh = runIdentity $ do
   let hidden = M.randomish (1,(fi nh)) (0,1) seed
       rb = newRBM seed (fi ni) (fi nh)
       fi ww = 1 + (fromIntegral ww)
       seed = (fi ni) * (fi nh)
   pp <- inputPs rb hidden
   return $ (fi ni) == (M.row pp)

prop_inputProbs2 :: Bool
prop_inputProbs2 = runIdentity $ do
   let i0 = w00 * h0 + w10 * h1
       i1 = w01 * h0 + w11 * h1
       i2 = w02 * h0 + w12 * h1
       h0:h1:_ = [1..]
       w00:w01:w02:w10:w11:w12:_ = [1..]
       wws = [w00,w01,w02,w10,w11,w12]
       hiddens = M.fromList (1,2) [h0,h1]
       rb = M.fromList (2,3) $ wws
   rb' <- M.transpose rb
   pp <- inputPs rb' hiddens
   pp' <- M.toList <$> M.transpose pp
   return $ pp' == map sigmoid [i0,i1,i2]

prop_energy :: Word8 -> Word8 -> Bool
prop_energy ni nh = runIdentity $ do
   let input = M.randomish (1, (fi ni)) (0,1) seed
       rb = newRBM seed (fi ni) (fi nh)
       fi ww = 1 + (fromIntegral ww)
       seed = (fi ni) * (fi nh)
   ee <- energy rb input
   return $ not $ isNaN ee


test :: IO ()
test = do
   let check rr = if (isSuccess rr) then return () else exitFailure
       cfg = stdArgs { maxSuccess = 100, maxSize = 10 }
       runtest tst p =  do putStrLn tst; check =<< verboseCheckWithResult cfg p
   runtest "init"      prop_init
   runtest "energy"    prop_energy
   runtest "hiddenp"   prop_hiddenProbs
   runtest "hiddenp2"  prop_hiddenProbs2
   runtest "inputp"    prop_inputProbs
   runtest "inputp2"   prop_inputProbs2
   runtest "learn"     prop_learn
   runtest "not_learn" prop_not_learn


perf :: IO ()
perf = do
   let file = "dist/perf-repa-RBM.html"
       cfg = defaultConfig { reportFile = Just file, timeLimit = 1.0 }
   defaultMainWith cfg [
       bgroup "energy" [ bench "63x63"  $ whnf (prop_energy 63) 63
                       , bench "127x127"  $ whnf (prop_energy 127) 127
                       , bench "255x255"  $ whnf (prop_energy 255) 255
                       ]
      ,bgroup "hidden" [ bench "63x63"  $ whnf (prop_hiddenProbs 63) 63
                       , bench "127x127"  $ whnf (prop_hiddenProbs 127) 127
                       , bench "255x255"  $ whnf (prop_hiddenProbs 255) 255
                       ]
      ,bgroup "input" [ bench "63x63"  $ whnf (prop_inputProbs 63) 63
                      , bench "127x127"  $ whnf (prop_inputProbs 127) 127
                      , bench "255x255"  $ whnf (prop_inputProbs 255) 255
                      ]
      ,bgroup "learn" [ bench "15"  $ whnf (prop_learn 15 15) 15
                      , bench "63x63"  $ whnf (prop_learn 63 63) 63
                      , bench "127x127"  $ whnf (prop_learn 127 127) 127
                      , bench "255x255"  $ whnf (prop_learn 255 255) 255
                      ]
      ]
   putStrLn $ "perf log written to " ++ file
