require 'deformableconvolution'
require 'nn'
local nninit= require 'nninit'

local DeformableConvolution, parent = torch.class('nn.DeformableConvolution', 'nn.Module')

function DeformableConvolution:__init(nInputPlane, nOutputPlane, kW, kH)
   parent.__init(self)


   self.nInputPlane = nInputPlane
   self.nOutputPlane = nOutputPlane
   self.kW = kW
   self.kH = kH
      

   self.weight = torch.Tensor(nOutputPlane, nInputPlane, kH, kW)
   self.bias = torch.Tensor(nOutputPlane)
   self.gradWeight = torch.Tensor(nOutputPlane, nInputPlane, kH, kW)
   self.gradBias = torch.Tensor(nOutputPlane)
   self.bufferIndices = torch.LongTensor()
   self.bufferInterpolationWeights = torch.Tensor()
   
   self.offsetPredictor = nn.SpatialConvolution(nInputPlane,2*kW*kH,kW,kH):init('weight',nninit.constant,0):init('bias', nninit.constant,0)
   
end

function DeformableConvolution:updateOutput(input)
    print('updateOutput')
    local wOutputImage = input:size(3)-self.kW+1
    local hOutputImage = input:size(2)-self.kH+1
    
    self.bufferIndices:resize(self.nInputPlane*self.kW*self.kH, hOutputImage*wOutputImage,3)
    self.bufferInterpolationWeights:resize(self.nInputPlane*self.kW*self.kH, wOutputImage*hOutputImage, 4)
    
    self.output:resize(self.nOutputPlane, hOutputImage, wOutputImage)
    
    offset = self.offsetPredictor:forward(input):view(
        hOutputImage
        ,wOutputImage
        ,self.kH
        ,self.kW
        ,2)
    assert(input:isContiguous())
    --unfoldedInput = torch.rand(self.nInputPlane*self.kH*self.kW,hOutputImage*wOutputImage)
    unfoldedInput = deformableconvolution.im2col(input,offset,self.kH,self.kW,self.bufferIndices,self.bufferInterpolationWeights,1)
    self.output = torch.mm(
        self.weight:view(self.nOutputPlane,self.nInputPlane*self.kW*self.kH)
        ,unfoldedInput
    ):view(self.nOutputPlane,hOutputImage, wOutputImage)
    
    for c2 = 1, self.nOutputPlane do
        self.output[c2]:add(self.bias[c2])
    end
    return self.output 
end
    
function DeformableConvolution:updateGradInput(input,gradOutput)
    local gradInput = torch.Tensor(input:size()):zero()
    local wOutputImage = input:size(3)-self.kW+1
    local hOutputImage = input:size(2)-self.kH+1

    gradIm2col = torch.mm(
        self.weight:view(
            self.nOutputPlane
            ,self.nInputPlane*self.kW*self.kH):transpose(1,2):contiguous()
        ,gradOutput:view(self.nOutputPlane, gradOutput:size(2)*gradOutput:size(3)))
    self.gradInput = deformableconvolution.update_grad_input(gradInput,gradIm2col,self.bufferIndices,self.bufferInterpolationWeights) 

    return self.gradInput
end
    
function DeformableConvolution:accGradParameters(input, gradOutput, scale)
    print('accGradParameters')
    scale = scale or 1
    
    local gradBias = torch.Tensor(self.gradBias:size()):zero()
    local gradWeight = torch.Tensor(self.gradWeight:size()):zero()
    
    local wOutputImage = input:size(3)-self.kW+1
    local hOutputImage = input:size(2)-self.kH+1
    
    ones = torch.Tensor(gradOutput:size(2),gradOutput:size(3)):fill(1)
    for i = 1, self.nOutputPlane do
        gradBias[i] = gradBias[i] + gradOutput[i]:dot(ones)
    end
    
    offsets = ((self.offsetPredictor).output):view(
        hOutputImage
        ,wOutputImage
        ,self.kH
        ,self.kW
        ,2)
        
    
    
    for c1star = 1, self.nInputPlane do
        for c2star = 1, self.nOutputPlane do
            assert(input[c1star]:view(1,input:size(2),input:size(3)):isContiguous())
            print(input[c1star]:view(1,input:size(2),input:size(3)):size())
            print((input:size(2)-gradOutput:size(2)+1)*(input:size(3)-gradOutput:size(3)+1))
            --input2col = torch.rand(gradOutput:size(2)*gradOutput:size(3), (input:size(2)-gradOutput:size(2)+1)*(input:size(3)-gradOutput:size(3)+1))
            input2col = deformableconvolution.im2col(
                    input[c1star]:view(1,input:size(2),input:size(3))
                    ,offsets:transpose(1,3):transpose(2,4):contiguous()
                    ,gradOutput:size(2)
                    ,gradOutput:size(3)
                    ,torch.LongTensor() -- empty long tensor for buffer indices
                    ,torch.Tensor() -- empty double tensor for buffer
                    ,0)
            assert(input2col:isContiguous())
--             print(gradOutput[c2star]:view(1,gradOutput:size(2)*gradOutput:size(3)):size(),input2col:size())
--             
--                     
--             print(torch.mm(
--                 gradOutput[c2star]:view(1,gradOutput:size(2)*gradOutput:size(3))
--                 ,input2col):view(self.kH,self.kW):size(), gradWeight[c2star][c1star]:size())  
--             
            gradWeight[c2star][c1star]:add(torch.mm(
                gradOutput[c2star]:view(1,gradOutput:size(2)*gradOutput:size(3))
                ,input2col
            ):view(self.kH,self.kW))
        end
            
    end
    
    self.gradBias:add(scale, gradBias)
    self.gradWeight:add(scale, gradWeight)
end


    
    
    
    
        
                    
            
    
    
        
