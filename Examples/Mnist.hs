--from https://github.com/mhwombat/backprop-example/blob/master/Mnist.hs
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FlexibleContexts #-}
module Examples.Mnist (generateTrainBatches
                      ,generateTrainLabels
                      ,generateTestBatches
                      ,readArray
                      ,generateBigTrainBatches
                      ,generateSamples
                      ,mnist
                      )where

import Control.Applicative((<|>))
import Control.Monad.Trans(liftIO)
import Control.Monad(when,forever,forM_)
import qualified Data.ByteString.Lazy as BL
import Data.Binary.Get hiding(label)
import qualified Data.Binary as B
import Data.Word
import qualified Data.List.Split as S
import qualified Data.Array.Repa as R
import Codec.Compression.GZip as GZ
import Data.List.Split(chunksOf)
import System.Random(newStdGen, randomRs)

import qualified Data.DNN.Trainer as T
import qualified Data.RBM as RB
import qualified Data.Matrix as M
import qualified Data.ImageUtils as I
import Data.Matrix(Matrix(..)
                  ,U
                  ,B
                  ,I
                  ,H
                  )



data Image = Image {
      iRows :: Int
    , iColumns :: Int
    , iPixels :: [Word8]
    } deriving (Eq, Show)

toMatrix :: [Image] -> R.Array R.U R.DIM2 Double
toMatrix images = m
  where 
        m = R.fromListUnboxed (R.Z R.:. len R.:. maxsz) (concatMap pixels images)
        maxsz = 1 + (maximum $ map (\ ii -> (iRows ii) * (iColumns ii)) images)
        len = length images
        pixels im = take maxsz $ 1:((normalisedData im) ++ [0..])

normalisedData :: Image -> [Double]
normalisedData image = map normalisePixel (iPixels image)

normalisePixel :: Word8 -> Double
normalisePixel p = (fromIntegral p) / 255.0

toLabelM :: [Int] -> R.Array R.U R.DIM2 Double
toLabelM labels = m
  where 
        m = R.fromListUnboxed (R.Z R.:. len R.:. 11) (concatMap labelVector labels)
        len = length labels

labelVector :: Int -> [Double]
labelVector ll = take 11 $ 1.0:(start ++ end)
   where start = take (ll - 1) $ repeat 0.0
         end = 1.0 : repeat 0.0


-- MNIST label file format
--
-- [offset] [type]          [value]          [description]
-- 0000     32 bit integer  0x00000801(2049) magic number (MSB first)
-- 0004     32 bit integer  10000            number of items
-- 0008     unsigned byte   ??               label
-- 0009     unsigned byte   ??               label
-- ........
-- xxxx     unsigned byte   ??               label
--
-- The labels values are 0 to 9.

deserialiseLabels :: Get (Word32, Word32, [Word8])
deserialiseLabels = do
  magicNumber <- getWord32be
  count <- getWord32be
  labelData <- getRemainingLazyByteString
  let labels = BL.unpack labelData
  return (magicNumber, count, labels)

readLabels :: FilePath -> IO [Int]
readLabels filename = do
  content <- GZ.decompress <$> BL.readFile filename
  let (_, _, labels) = runGet deserialiseLabels content
  return (map fromIntegral labels)


-- MNIST Image file format
--
-- [offset] [type]          [value]          [description]
-- 0000     32 bit integer  0x00000803(2051) magic number
-- 0004     32 bit integer  ??               number of images
-- 0008     32 bit integer  28               number of rows
-- 0012     32 bit integer  28               number of columns
-- 0016     unsigned byte   ??               pixel
-- 0017     unsigned byte   ??               pixel
-- ........
-- xxxx     unsigned byte   ??               pixel
-- 
-- Pixels are organized row-wise. Pixel values are 0 to 255. 0 means background (white), 255 
-- means foreground (black). 
 
deserialiseHeader :: Get (Word32, Word32, Word32, Word32, [[Word8]])
deserialiseHeader = do
  magicNumber <- getWord32be
  imageCount <- getWord32be
  r <- getWord32be
  c <- getWord32be
  packedData <- getRemainingLazyByteString
  let len = fromIntegral (r * c)
  let unpackedData = S.chunksOf len (BL.unpack packedData)
  return (magicNumber, imageCount, r, c, unpackedData)

readImages :: FilePath -> IO [Image]
readImages filename = do
  content <- GZ.decompress <$> BL.readFile filename
  let (_, _, r, c, unpackedData) = runGet deserialiseHeader content
  return (map (Image (fromIntegral r) (fromIntegral c)) unpackedData)

writeArray :: String -> R.Array R.U R.DIM2 Double -> IO ()
writeArray fileName array = do 
   let (R.Z R.:. r R.:. c) = R.extent array
   B.encodeFile fileName (r,c,R.toList array)

readArray ::String -> IO (R.Array R.U R.DIM2 Double)
readArray fileName = do 
   (r,c,ls) <- B.decodeFile fileName
   return $ R.fromListUnboxed  (R.Z R.:. r R.:. c) ls

generateTrainBatches :: IO ()
generateTrainBatches = do
   images <- readImages "dist/train-images-idx3-ubyte.gz"
   let batches = map toMatrix $ chunksOf 128 images
   (flip mapM_) (zip [0::Integer ..] batches) $ \ (ix, bb) -> do
      let name = "dist/train" ++ (show ix)
      writeArray name bb 

generateTrainLabels :: IO ()
generateTrainLabels = do
   labels <- readLabels "dist/train-labels-idx1-ubyte.gz"
   let batches = map toLabelM $ chunksOf 128 labels
   (flip mapM_) (zip [0::Integer ..] batches) $ \ (ix, bb) -> do
      let name = "dist/label" ++ (show ix)
      writeArray name bb 

generateTestBatches :: IO ()
generateTestBatches = do
   images <- readImages "dist/t10k-images-idx3-ubyte.gz"
   labels <- readLabels "dist/t10k-labels-idx1-ubyte.gz"
   (flip mapM_) ([0..9]) $ \ ix -> do
      let name = "dist/test" ++ (show ix)
      let batch = filter (((==) ix) . fst) $ zip labels images
      let bb = toMatrix $ snd $ unzip batch 
      writeArray name bb 

generateBigTrainBatches :: IO ()
generateBigTrainBatches = do
   images <- readImages "dist/train-images-idx3-ubyte.gz"
   labels <- readLabels "dist/train-labels-idx1-ubyte.gz"
   (flip mapM_) ([0..9]) $ \ ix -> do
      let name = "dist/bigtrain" ++ (show ix)
      let batch = filter (((==) ix) . fst) $ zip labels images
      let bb = toMatrix $ snd $ unzip batch 
      writeArray name bb 

generateSamples :: IO ()
generateSamples = do
   images <- readImages "dist/train-images-idx3-ubyte.gz"
   labels <- readLabels "dist/train-labels-idx1-ubyte.gz"
   (flip mapM_) ([0..9]) $ \ ix -> do
      gen <- newStdGen
      let name = "dist/sample" ++ (show ix)
      let batch = filter (((==) ix) . fst) $ zip labels images
          batches = snd $ unzip batch
          len = length batches
          rbatches = take 10 $ map (\ rr -> head $ drop rr $ cycle $ batches) (randomRs (0::Int, len - 1) gen)
      let bb = toMatrix $ rbatches 
      writeArray name bb 

readBatch :: Int -> IO (Matrix U B I)
readBatch ix = Matrix <$> readArray name
   where name = "dist/train" ++ (show ix)

readLabel :: Int -> IO (Matrix U B H)
readLabel ix = Matrix <$> readArray name
   where name = "dist/label" ++ (show ix)

maxCount :: Int
maxCount = 100000
testCount :: Int
testCount = 10000
rowCount :: Int
rowCount = 1

trainCD :: String -> Double ->  T.Trainer IO ()
trainCD file mine = forever $ do
  T.setLearnRate 0.001
  let batchids = [0..468::Int]
  forM_ batchids $ \ ix -> do
     big <- liftIO $ readBatch ix
     small <- mapM M.d2u $ M.splitRows rowCount big
     forM_ small $ \ batch -> do
        T.contraDiv batch
        cnt <- T.getCount
        when (0 == cnt `mod` testCount) $ do
           nns <- T.getDNN
           ww <- M.cast1 <$> M.transpose (last nns)
           liftIO $ I.writeGIF file ww
        when (0 == cnt `mod` testCount) $ do
           err <- T.reconErr big
           liftIO $ print (cnt, err)
           when (cnt >= maxCount || err < mine) $ T.finish_

trainBP :: String -> Double -> T.Trainer IO ()
trainBP file mine = forever $ do
  T.setLearnRate 0.001
  let batchids = [0..468::Int]
  forM_ batchids $ \ ix -> do
     bbatch <- liftIO $ readBatch ix
     blabel <- liftIO $ readLabel ix
     sbatch <- mapM M.d2u $ M.splitRows rowCount bbatch
     slabel <- mapM M.d2u $ M.splitRows rowCount blabel
     forM_ (zip sbatch slabel) $ \ (batch,label) -> do
        T.backProp batch label
        cnt <- T.getCount
        when (0 == cnt `mod` testCount) $ do
           gen <- T.backward (Matrix $ toLabelM [0..9])
           liftIO $ I.writeGIF file gen
        when (0 == cnt `mod` testCount) $ do
           err <- T.forwardErr bbatch blabel
           liftIO $ print (cnt, err)
           when (cnt >= maxCount || err < mine) $ T.finish_

testBatch :: [Matrix U I H] -> Int -> IO ()
testBatch nns ix = do
   let name = "dist/test" ++ (show ix)
   bxi <- Matrix <$> readArray name
   let bxh = M.fromList (M.row bxi, 11) $ concat $ replicate (M.row bxi) $ labelVector ix
   (err,_) <- T.run nns $ T.forwardErr bxi bxh
   print (ix, err)

mnist :: IO ()
mnist = do 
   let r1 = RB.new 0 785 530
       r2 = RB.new 0 530 530
       r3 = RB.new 0 530 11
  
   --train the first layer
   tr1 <- B.decodeFile "dist/rbm1"
      <|> snd <$> (T.run [r1] $ trainCD "dist/rbm1.gif" 0.01)
   B.encodeFile "dist/rbm1" tr1

   --train the second layer
   tr2 <- B.decodeFile "dist/rbm2"
      <|> (snd <$> (T.run (tr1++[r2]) $ trainCD "dist/rbm2.gif" 0.0001))
   B.encodeFile "dist/rbm2" tr2

   --train the third layer
   tr3 <- B.decodeFile "dist/rbm3" 
      <|> (snd <$> (T.run (tr2++[r3]) $ trainCD "dist/rbm3.gif" 0.0001))
   B.encodeFile "dist/rbm3" tr3

   --backprop
   bp1 <- B.decodeFile "dist/bp1" 
      <|> (snd <$> (T.run tr3 $ trainBP "dist/bp1.gif" 0.001))
   B.encodeFile "dist/bp1" bp1

   bp2 <- B.decodeFile "dist/bp2" 
      <|> (snd <$> (T.run bp1 $ trainBP "dist/bp2.gif" 0.001))
   B.encodeFile "dist/bp2" bp2

   mapM_ (testBatch bp2) [0..9] 



