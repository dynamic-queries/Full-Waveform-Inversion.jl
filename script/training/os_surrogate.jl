using NeuralOperators
using Flux
using Flux:splitobs 
using FluxOptTools
using BSON: @load
using HDF5
using CUDA
using Zygote
include("../../src/train.jl")

device = gpu
CUDA.allowscalar(false)


# We know apriori that the problem was solved in the domain.
# x ∈ [0,1]
# y ∈ [0,1]
# With a resolution of 199 internal points.

x = 0.0:(1.0)/200:1.0
y = 0.0:(1.0)/200:1.0

X = reshape([xi for xi in x for _ in y],(length(x),length(y)))
Y = reshape([yi for _ in x for yi in y],(length(x),length(y)))

## Data
filename = "big_data/dynamic/GROUND_TRUTH"

batches = 1:180
BS = length(batches)
nx = length(x)
ny = length(y)

xdata = Array{Float64,4}(undef,3,nx,ny,BS)
ydata = Array{Float64,4}(undef,1,nx,ny,BS)

# One shot training.
for (i,b) in enumerate(batches)
    file = h5open(string(filename,b),"r")
    xdata[1,:,:,i] .= read(file["1"])
    xdata[2,:,:,i] .= X 
    xdata[3,:,:,i] .= Y
    ydata[1,:,:,i] .= read(file["501"])
end     

print("Read Data...\n")

# DataLoader
traind,testd = splitobs((xdata,ydata),at=0.9)
train_loader = Flux.DataLoader(traind,batchsize=2,shuffle=true)
test_loader = Flux.DataLoader(testd,batchsize=1,shuffle=false)

# Model
nmodes = 8
DL = 16
 
model = Chain(
        Dense(3,DL),
        OperatorKernel(DL=>DL, (nmodes,nmodes), FourierTransform, gelu),
        OperatorKernel(DL=>DL, (nmodes,nmodes), FourierTransform, gelu),
        OperatorKernel(DL=>DL, (nmodes,nmodes), FourierTransform, gelu),
        OperatorKernel(DL=>DL, (nmodes,nmodes), FourierTransform, gelu),
        Dense(DL,DL),
        Dense(DL,1)
) |> device

# Optimizer params
lossfunction = l₂loss
data = (train_loader,test_loader)
foldername = "weights/os/64/"

if !isdir(foldername)
    mkdir(foldername)
end 

print("Training model... \n")

logger = TBLogger("script/logs/os")

lr = 1e-2
nepochs = 10
opt = Flux.Adam(lr)
learn(model,lossfunction,data,opt,nepochs,foldername)

lr = 1e-3
nepochs = 500
opt = Flux.Adam(lr)
learn(model,lossfunction,data,opt,nepochs,foldername)

# BGFS needs to run on a smaller dataset
# for iter=1:36
    # start = (iter-1)*5
    # x = xdata[:,:,:,start+1:start+5] |> device
    # y = ydata[:,:,:,start+1:start+5] |> device
    # lossbfgs() = lossfunction(model(x),y)
    # Zygote.refresh()
    # pars   = Flux.params(model)
    # lossfun, gradfun, fg!, p0 = optfuns(lossbfgs, pars)
    # res = Optim.optimize(Optim.only_fg!(fg!), p0, Optim.Options(iterations=100, store_trace=true))
# end 